import urllib.request
import json

url = "https://siaga-polda-kalsel-default-rtdb.asia-southeast1.firebasedatabase.app/users.json"
try:
    response = urllib.request.urlopen(url)
    data = json.loads(response.read().decode('utf-8'))
    for uid, user in data.items():
        if user:
            print(f"UID: {uid}")
            print(f"  NRP: {user.get('nrp')}")
            print(f"  Nama: {user.get('nama')}")
            print(f"  Email: {user.get('email')}")
            print(f"  Pangkat: {user.get('pangkat')}")
            print(f"  Status: {user.get('status')}")
            print(f"  Waktu Daftar: {user.get('waktu_daftar')}")
            print("-" * 40)
except Exception as e:
    print(f"Error: {e}")
