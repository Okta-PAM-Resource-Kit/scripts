import json
import os
import random
import requests
import string

from jwcrypto import jwe, jwk

host = "https://<<Okta Subdomain>>.pam.oktapreview.com"
team = "<<OPA TEAM Name"
client = "<<Service Account Key ID>>"
secret = "OPA Service Account Key Secret>>"
resource_group_id = "<<REsource Group ID>>"
project_id = "<<Project ID>>"
secret_id = "<<Secret ID for updates>>" #hardcoded for this script as demo here but can be dynamic
parent_secret_folder_id = "<<Secret Parent folder ID>>"

def load_configuration():
    global host, team, client, secret, resource_group_id, project_id, parent_secret_folder_id
    host = get_or_raise_env_var("OKTAPAM_API_HOST")
    team = get_or_raise_env_var("OKTAPAM_TEAM")
    client = get_or_raise_env_var("OKTAPAM_KEY")
    secret = get_or_raise_env_var("OKTAPAM_SECRET")
    resource_group_id = get_or_raise_env_var("OKTAPAM_RESOURCE_GROUP_ID")
    project_id = get_or_raise_env_var("OKTAPAM_PROJECT_ID")
    parent_secret_folder_id = get_or_raise_env_var("OKTAPAM_PARENT_SECRET_FOLDER_ID")

def get_or_raise_env_var(var: str) -> str:
    try:
        val = os.environ[var]
        return val
    except KeyError:
        raise RuntimeError(f"expected environment variable of {var} to be set")

def login() -> str:
    authorization_url = f"{host}/v1/teams/{team}/service_token"
    authorization_body = {"key_id": client, "key_secret": secret}
    authorization_response = requests.post(authorization_url, json=authorization_body)

    if authorization_response.status_code != 200:
        raise RuntimeError("could not login")

    response_json = authorization_response.json()
    bearer_token = response_json["bearer_token"]

    return bearer_token

def get_jwks(bearer: str):
    print("obtaining JWKS from OPA")
    jwks_url = f"{host}/v1/teams/{team}/vault/jwks.json"
    jwks_response = requests.get(jwks_url, headers={"Authorization": f"Bearer {bearer}"})
    if jwks_response.status_code != 200:
        raise RuntimeError("could not obtain jwks")

    jwks_json = jwks_response.json()
    try: 
        keys = jwks_json["keys"]
        if len(keys) == 0:
            raise RuntimeError("jwks response did not contain any keys")
        return json.dumps(keys[0])
    except:
        raise RuntimeError("jwks response did not contain any keys")

def create_secret(bearer: str, key_json_str) -> str:
    print("key_json_str -->> "+key_json_str)
    key = jwk.JWK.from_json(key_json_str)
    print("-"*80)
    print(key)
    print("-"*80)
    secret_name = "".join(random.choices(string.ascii_uppercase + string.digits, k=10))
    print("secret_name  --->> "+secret_name)

    secret_data = json.dumps({"test": "this is a secret","test1": "this is a secret1"})
    print("secret_data  --->> "+secret_data)

    encrypted_data = jwe.JWE(secret_data.encode("utf-8"), recipient=key, protected={"enc": "A256GCM", "alg": key["alg"], "kid": key["kid"]})
    
    print("-"*80)
    print(encrypted_data)
    print("-"*80)

    print(encrypted_data.serialize())
    print("="*80)


    payload = {"name": secret_name, "secret_jwe": encrypted_data.serialize(), "parent_folder_id": parent_secret_folder_id}

    create_secret_url = f"{host}/v1/teams/{team}/resource_groups/{resource_group_id}/projects/{project_id}/secrets"
    create_secret_response = requests.post(create_secret_url, json=payload, headers={"Authorization": f"Bearer {bearer}"})

    if create_secret_response.status_code != 201:
        print("error creating secret")
        print(create_secret_response.json())
        return

    response_json = create_secret_response.json()

    print(f"created a secret with id of {response_json['id']} and secret of '{secret_data}'")
    
    return response_json['id']


def update_secret(bearer: str, key_json_str) -> str:
    print("update_secret -->> key_json_str -->> "+key_json_str)
    key = jwk.JWK.from_json(key_json_str)

    secret_name = "QN2S3ML9PO"
    secret_data = json.dumps({"test123": "this is a secret","test1234": "this is a secret"})

    encrypted_data = jwe.JWE(secret_data.encode("utf-8"), recipient=key, protected={"enc": "A256GCM", "alg": key["alg"], "kid": key["kid"]})
    
    payload = {"name": secret_name, "secret_jwe": encrypted_data.serialize(), "parent_folder_id": parent_secret_folder_id}

    update_secret_url = f"{host}/v1/teams/{team}/resource_groups/{resource_group_id}/projects/{project_id}/secrets/{secret_id}"
    update_secret_response = requests.put(update_secret_url, json=payload, headers={"Authorization": f"Bearer {bearer}"})

    if update_secret_response.status_code != 201:
        print("error creating secret")
        print(update_secret_response.json())
        return

    response_json = update_secret_response.json()

    print(f"updated a secret with id of {response_json['id']} and secret of '{secret_data}'")
    
    return response_json['id']

def reveal_secret(bearer: str, secret_id: str):
    kid = "".join(random.choices(string.ascii_uppercase + string.digits, k=10))
    key = jwk.JWK.generate(kty='RSA', size=2048, kid=kid)
    exported_public = json.loads(key.export(private_key=False))

    reveal_secret_url = f"{host}/v1/teams/{team}/resource_groups/{resource_group_id}/projects/{project_id}/secrets/{secret_id}"
    payload = {"public_key": exported_public}
    reveal_secret_response = requests.post(reveal_secret_url, json=payload, headers={"Authorization": f"Bearer {bearer}"})

    if reveal_secret_response.status_code != 200:
        print("error revealing secret")
        print(reveal_secret_response.json())
        return

    response_json = reveal_secret_response.json()
    secret_jwe = jwe.JWE.from_jose_token(response_json['secret_jwe'])
    secret_jwe.decrypt(key)
    decrypted_secret = secret_jwe.payload.decode('utf-8')

    print(f"revealed the secret with id of {secret_id} and secret of '{decrypted_secret}'")

def main():
  #  load_configuration()
    bearer = login()
    key = get_jwks(bearer)
    print("key --->> " + key)
    create_secret_id = create_secret(bearer, key)
    reveal_secret(bearer, create_secret_id)
    #update_secret_id = update_secret(bearer, key)
    #reveal_secret(bearer, secret_id)
    

if __name__ == "__main__":
    main()
