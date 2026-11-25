#!/usr/bin/env python3
"""H-007 task 2: does kagent's oauth2-proxy accept an ID token of research-mcp-claude?

Signs you in through the research-mcp-claude Cognito client (browser, PKCE, Identity
Center), then calls research-agent's A2A agent card on the kagent host, the same path
and proxy the Slack bridge uses. Tokens stay in this process: never printed or saved.

Run from an allowed address with the hub up and AWS signed in:
    AWS_PROFILE=agentgrid python3 scripts/check-research-mcp-token.py
Needs the TEMPORARY http://localhost:8976/callback on the client (openbao-platform
layer 25); remove it in H-007 task 3.
"""
import base64, hashlib, http.server, json, os, secrets, subprocess, sys, threading
import urllib.error, urllib.parse, urllib.request, webbrowser

PORT = 8976
REDIRECT = f"http://localhost:{PORT}/callback"
HOST = os.environ.get("KAGENT_HOST", "https://kagent.edwardpius.me")
CARD = f"{HOST}/agents/kagent/research-agent/.well-known/agent-card.json"
COGNITO = os.path.expanduser(os.environ.get("COGNITO_LAYER", "~/openbao/infra/25-cognito"))
IDP = os.environ.get("COGNITO_IDP", "IdentityCenter")


def tf_out(name):
    return subprocess.run(["terraform", f"-chdir={COGNITO}", "output", "-raw", name],
                          check=True, capture_output=True, text=True).stdout.strip()


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def claims(jwt):
    p = jwt.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))


def get(url, token=None):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"} if token else {})
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=20) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def token_call(domain, form):
    req = urllib.request.Request(f"https://{domain}/oauth2/token",
                                 data=urllib.parse.urlencode(form).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def sign_in(domain, client_id):
    verifier = b64url(secrets.token_bytes(32))
    state = b64url(secrets.token_bytes(16))
    got = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Signed in. You can close this tab and go back to the terminal.")

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=srv.handle_request, daemon=True).start()
    url = f"https://{domain}/oauth2/authorize?" + urllib.parse.urlencode({
        "response_type": "code", "client_id": client_id, "redirect_uri": REDIRECT,
        "scope": "openid email profile", "identity_provider": IDP, "state": state,
        "code_challenge": b64url(hashlib.sha256(verifier.encode()).digest()),
        "code_challenge_method": "S256"})
    print("Opening the browser to sign in (Identity Center)...")
    webbrowser.open(url)
    print(f"If it didn't open, visit:\n  {url}\n")
    while "code" not in got and "error" not in got:
        threading.Event().wait(0.5)
    srv.server_close()
    if got.get("error"):
        sys.exit(f"sign-in failed: {got.get('error')} {got.get('error_description', '')}")
    if got.get("state") != state:
        sys.exit("sign-in failed: state mismatch")
    return token_call(domain, {"grant_type": "authorization_code", "client_id": client_id,
                               "code": got["code"], "redirect_uri": REDIRECT,
                               "code_verifier": verifier})


results = []


def check(name, ok, detail):
    results.append(ok)
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")


def main():
    domain, client_id, issuer = tf_out("hosted_ui_domain"), tf_out("research_mcp_client_id"), tf_out("issuer")
    if not client_id:
        sys.exit("research_mcp_client_id is empty: apply layer 25 first")
    tok = sign_in(domain, client_id)
    idt = tok["id_token"]
    c = claims(idt)
    print("ID token (claims only):")
    for k in ("iss", "aud", "token_use", "sub", "identities"):
        v = c.get(k)
        if k == "identities" and v:
            v = [i.get("userId") for i in v]
        print(f"  {k}: {v}")
    check("token is for this client", c.get("aud") == client_id and c.get("iss") == issuer
          and c.get("token_use") == "id", f"aud={c.get('aud')}")

    print(f"Calls to {CARD}:")
    s, body = get(CARD)
    check("no token is refused", s in (302, 401, 403), f"HTTP {s}")
    s, body = get(CARD, idt)
    name = ""
    try:
        name = json.loads(body).get("name", "")
    except Exception:
        pass
    check("research-mcp-claude ID token accepted", s == 200, f"HTTP {s} {name!r}")
    h, p, sig = idt.split(".")
    forged = f"{h}.{p}.{sig[:-4]}{'AAAA' if sig[-4:] != 'AAAA' else 'BBBB'}"
    s, _ = get(CARD, forged)
    check("token with a broken signature refused", s in (401, 403), f"HTTP {s}")
    payload = claims(idt)
    payload["aud"] = "someone-else"
    other = f"{h}.{b64url(json.dumps(payload).encode())}.{sig}"
    s, _ = get(CARD, other)
    check("token with another audience refused", s in (401, 403), f"HTTP {s}")
    if tok.get("access_token"):
        s, _ = get(CARD, tok["access_token"])
        check("access token (not ID token) refused", s in (401, 403), f"HTTP {s} (why REQ-03 hands claude.ai the ID token)")

    if tok.get("refresh_token"):
        new = token_call(domain, {"grant_type": "refresh_token", "client_id": client_id,
                                  "refresh_token": tok["refresh_token"]})
        s, _ = get(CARD, new.get("id_token", ""))
        check("refreshed ID token accepted", s == 200, f"HTTP {s}")

    print(f"\nsub for the principal check: {c.get('sub')}")
    print(f"{sum(results)} of {len(results)} passed")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
