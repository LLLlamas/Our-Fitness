#!/usr/bin/env python3
"""Diagnose the Actions signing credential without logging secret values."""

import base64
import binascii
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.request


def fail(message):
    print(f"::error::{message}")
    raise SystemExit(1)


def credentials(env):
    url = env.get("MATCH_GIT_URL", "")
    match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?", url)
    if not match:
        fail("MATCH_GIT_URL must be https://github.com/OWNER/REPO.git with no whitespace or embedded credentials.")
    encoded = env.get("MATCH_GIT_BASIC_AUTHORIZATION", "")
    try:
        decoded = base64.b64decode(encoded, validate=True).decode("ascii")
    except (ValueError, binascii.Error, UnicodeError):
        fail("MATCH_GIT_BASIC_AUTHORIZATION is not single-line Base64 of username:PAT.")
    username, separator, token = decoded.partition(":")
    if not separator or not username or not token or ":" in token or any(c.isspace() for c in decoded):
        fail("MATCH_GIT_BASIC_AUTHORIZATION decodes, but is not a nonempty username:PAT pair without whitespace.")
    return url, "/".join(match.groups()), encoded, token


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def api_status(path, token):
    request = urllib.request.Request(
        "https://api.github.com" + path,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "Our-Fitness-signing-preflight"},
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except (urllib.error.URLError, TimeoutError):
        fail("Cannot reach GitHub API to diagnose signing access (network/TLS error).")


def main():
    url, repository, encoded, token = credentials(os.environ)
    print("Signing URL and Base64 username:PAT format are valid.")
    status = api_status("/user", token)
    if status != 200:
        fail(f"GitHub token identity check returned HTTP {status}. " +
             ("The saved PAT is rejected; it may be expired, revoked, or copied incorrectly."
              if status == 401 else "GitHub did not accept the identity request; check account policy or API availability."))
    print("GitHub accepts the PAT stored in the Actions secret.")
    status = api_status("/repos/" + repository, token)
    if status != 200:
        fail(f"Signing repository metadata check returned HTTP {status}. " +
             ("The token is valid, but this repository is missing or inaccessible to it."
              if status == 404 else "Check repository policy/access, a moved repository URL, or API availability."))
    print("The saved PAT can access the signing repository metadata.")
    # Git authentication and Contents access are distinct from API metadata access.
    # Pass the header through the environment, not a command argument, and never
    # print Git stderr (a future Git version could echo credential-bearing data).
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_COUNT="1",
               GIT_CONFIG_KEY_0="http.extraHeader",
               GIT_CONFIG_VALUE_0="Authorization: Basic " + encoded)
    try:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["git", "ls-remote", url], env=env, cwd=directory,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
    except subprocess.TimeoutExpired:
        fail("Git signing repository access timed out after the API checks passed.")
    if result.returncode:
        fail("GitHub accepts the PAT and repository metadata access, but Git ls-remote failed. Check Contents read access and Git HTTP authentication configuration; secret values and Git stderr are suppressed.")
    print("Signing repository Git read access succeeded with the saved credential.")


if __name__ == "__main__":
    main()
