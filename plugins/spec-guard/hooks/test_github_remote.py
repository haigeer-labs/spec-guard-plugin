"""github_remote.py: origin-URL parsing, table-driven positive + negative cases."""
import unittest

from github_remote import is_github_remote, remote_host, repository_from_remote


POSITIVE = [
    ("https classic", "https://github.com/Owner/Repo.git", "Owner/Repo"),
    ("https no .git", "https://github.com/Owner/Repo", "Owner/Repo"),
    ("ssh with user", "git@github.com:Owner/Repo.git", "Owner/Repo"),
    ("ssh host alias with user", "git@github-alias:Owner/Repo.git", "Owner/Repo"),
    ("https trailing slash", "https://github.com/Owner/Repo/", "Owner/Repo"),
    ("https .git + trailing slash", "https://github.com/Owner/Repo.git/", "Owner/Repo"),
    ("uppercase .GIT suffix", "git@github.com:Owner/Repo.GIT", "Owner/Repo"),
    ("scp alias without user", "github-alias:Owner/Repo.git", "Owner/Repo"),
    ("scp alias without user, no .git", "github-alias:Owner/Repo", "Owner/Repo"),
]

NEGATIVE = [
    ("non-github https host", "https://gitlab.com/o/r.git"),
    ("non-github ssh host", "git@gitlab.com:o/r.git"),
    ("gitlab host with github in path", "https://gitlab.com/me/github-tools.git"),
    ("three segments", "https://github.com/o/r/extra"),
    ("empty repo segment", "https://github.com/Owner/"),
    ("empty owner segment", "https://github.com//Repo"),
    ("local path with colon-free alias", "/tmp/repo"),
    ("bare local path", "repo"),
    ("empty string", ""),
    ("scp alias, host part has slash", "not-github/alias:Owner/Repo.git"),
]


class RemoteHostTests(unittest.TestCase):
    def test_host_extraction_examples(self):
        cases = [
            ("https://github.com/o/r.git", "github.com"),
            ("git@github.com:o/r.git", "github.com"),
            ("git@github-alias:o/r.git", "github-alias"),
            ("github-alias:o/r.git", "github-alias"),
            ("https://gitlab.com/me/github-tools.git", "gitlab.com"),
        ]
        for url, expected in cases:
            with self.subTest(url=url):
                self.assertEqual(remote_host(url), expected)

    def test_is_github_remote_matches_host_only(self):
        self.assertTrue(is_github_remote("git@github-collab:o/r.git"))
        self.assertFalse(is_github_remote("https://gitlab.com/me/github-tools.git"))


class RepositoryFromRemoteTests(unittest.TestCase):
    def test_positive_cases(self):
        for name, url, expected in POSITIVE:
            with self.subTest(name=name, url=url):
                self.assertEqual(repository_from_remote(url), expected)

    def test_negative_cases(self):
        for name, url in NEGATIVE:
            with self.subTest(name=name, url=url):
                self.assertIsNone(repository_from_remote(url))


if __name__ == "__main__":
    unittest.main()
