"""One-time sign-in with your Bose account. The password is not stored, only the tokens."""

import getpass
import time

import jwt
from pybose.BoseAuth import BoseAuth

import tokenstore


def main() -> None:
    email = input("Bose account email: ").strip()
    password = getpass.getpass("Password: ")

    auth = BoseAuth()
    token = auth.getControlToken(email, password, forceNew=True)
    tokenstore.save({
        "access_token": token["access_token"],
        "refresh_token": token["refresh_token"],
        "azure_refresh_token": auth.get_azure_refresh_token(),
        "bose_person_id": token["bose_person_id"],
    })

    exp = jwt.decode(token["access_token"], options={"verify_signature": False})["exp"]
    print(f"Signed in. Token valid until {time.strftime('%Y-%m-%d %H:%M', time.localtime(exp))}.")
    print(f"Tokens are stored in the Keychain (service '{tokenstore.SERVICE}'). SoundbarKeys refreshes them automatically.")


if __name__ == "__main__":
    main()
