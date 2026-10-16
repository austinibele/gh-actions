"""Exercise command-scoped authentication with real Git config and child processes."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "lib/github-git.sh"
TOKEN = "diagnostic-token"
HEADER = "AUTHORIZATION: basic " + base64.b64encode(
    f"x-access-token:{TOKEN}".encode()
).decode()


class GithubGitTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="github-git-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.global_config = self.root / "global.gitconfig"
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key not in ("PAT", "NODE_AUTH_TOKEN", "GITHUB_ACTIONS")
        }
        self.env.update({
            "GIT_CONFIG_GLOBAL": str(self.global_config),
            "GIT_CONFIG_SYSTEM": os.devnull,
            "PAT": TOKEN,
        })
        self.git("init", "--quiet", str(self.root))
        self.git("config", "--global", "http.https://github.com/.extraheader", "old-global")
        self.git("config", "--local", "http.https://github.com/.extraheader", "old-checkout")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, env=self.env, check=True,
            capture_output=True, text=True,
        )

    def authenticated(self, *args):
        return subprocess.run(
            ["bash", str(SCRIPT), *args], cwd=self.root, env=self.env,
            capture_output=True, text=True,
        )

    def test_replaces_inherited_checkout_header_without_writing_config(self):
        files = [self.global_config, self.root / ".git/config"]
        before = [file.read_bytes() for file in files]
        result = self.authenticated("config", "--get-urlmatch", "http.extraheader", "https://github.com/myvisausa/crm")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), HEADER)
        self.assertEqual([file.read_bytes() for file in files], before)

    def test_authentication_reaches_child_git_processes(self):
        self.git("config", "alias.read-child", "!git config --get-urlmatch http.extraheader https://github.com/myvisausa/crm")
        result = self.authenticated("read-child")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), HEADER)

    def test_header_does_not_apply_to_other_hosts(self):
        result = self.authenticated("config", "--get-urlmatch", "http.extraheader", "https://example.invalid/repo")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_accepts_remote_backend_token_variable(self):
        self.env.pop("PAT")
        self.env["NODE_AUTH_TOKEN"] = TOKEN
        result = self.authenticated("config", "--get-urlmatch", "http.extraheader", "https://github.com/myvisausa/crm")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), HEADER)

    def test_fails_without_a_token(self):
        self.env.pop("PAT")
        result = self.authenticated("--version")
        self.assertEqual(result.returncode, 1)
        self.assertIn("requires PAT or NODE_AUTH_TOKEN", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_preserves_git_failure_status(self):
        result = self.authenticated("rev-parse", "--verify", "refs/heads/missing")
        self.assertEqual(result.returncode, 128)

    def test_change_detection_uses_the_header_without_writing_config(self):
        config = self.global_config.read_bytes()
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; shift; _github_git "$@"', "_",
             str(SCRIPT.with_name("change-detection.sh")), "config", "--get-urlmatch",
             "http.extraheader", "https://github.com/myvisausa/crm"],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), HEADER)
        self.assertEqual(self.global_config.read_bytes(), config)

    def test_change_detection_allows_public_access_without_a_token(self):
        self.env.pop("PAT")
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; _github_git --version', "_",
             str(SCRIPT.with_name("change-detection.sh"))],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("git version"))

    def test_masks_encoded_credentials_in_actions(self):
        self.env["GITHUB_ACTIONS"] = "true"
        result = self.authenticated("--version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("::add-mask::" + HEADER.split()[-1] + "\n"))
        self.assertNotIn(TOKEN, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
