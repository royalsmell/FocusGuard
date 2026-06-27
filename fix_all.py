import os
import base64

base_dir = os.getcwd()

def write_b64(path, b64_content):
    full = os.path.join(base_dir, path)
    with open(full, 'w') as f:
        f.write(base64.b64decode(b64_content).decode('utf-8'))

# Did the binary build? Let's check.
