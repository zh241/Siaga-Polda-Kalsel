import subprocess

result = subprocess.run(
    ['node', '--input-type=module'],
    input=open('c:/Users/User/siaga-polda-kalsel/app.js', 'rb').read(),
    capture_output=True
)
out = result.stdout.decode() + result.stderr.decode()
print(out if out else "No output / OK")
