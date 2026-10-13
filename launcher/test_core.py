"""File transaction tests with synthetic payloads. Never starts Godot."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import padding,rsa
import core

class Updates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        cls.public=cls.key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo)

    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.root=Path(self.temporary.name)
        (self.root/"versions"/"0.1.0").mkdir(parents=True)
        (self.root/core.BOOT).write_bytes(b"old")
        core.atomic_json(self.root/"installation.json",{"app":core.APP,"current":"0.1.0","previous":"","pending":False})
        (self.root/"userdata").mkdir()
        (self.root/"userdata"/"identity.json").write_text('keep identity')

    def tearDown(self):self.temporary.cleanup()

    def package(self,extra=None):
        data={"program/"+core.ENTRY:b"new game","boot/"+core.BOOT:b"new boot"}
        if extra:data.update(extra)
        import hashlib
        files={name:{"size":len(value),"sha256":hashlib.sha256(value).hexdigest()} for name,value in data.items()}
        record={"schema":1,"app":core.APP,"platform":"win-x64","version":"0.1.1","launcher_format":1,"data_formats":{"tokens":[1,2],"platforms":[2],"maps":[1],"adventures":[1]},"files":files,"unpacked_size":sum(map(len,data.values()))}
        raw=json.dumps(record).encode()
        sig=base64.b64encode(self.key.sign(raw,padding.PSS(mgf=padding.MGF1(hashes.SHA256()),salt_length=padding.PSS.DIGEST_LENGTH),hashes.SHA256()))
        path=self.root/"update.zip"
        with zipfile.ZipFile(path,"w") as package:
            package.writestr("release.json",raw);package.writestr("release.sig",sig)
            for name,value in data.items():package.writestr(name,value)
        return path,raw,sig

    def test_signature_rejected(self):
        _,raw,sig=self.package()
        with self.assertRaises(core.UpdateError):core.verified(raw+b" ",sig,self.public)

    def test_traversal_rejected(self):
        package,_,_=self.package({"program/../../identity.json":b"bad"})
        with self.assertRaises(core.UpdateError):core.stage(self.root,package,self.public)
        self.assertEqual((self.root/"userdata/identity.json").read_text(),'keep identity')

    def test_apply_and_confirm(self):
        package,_,_=self.package()
        core.stage(self.root,package,self.public)
        core.apply(self.root,self.public)
        self.assertEqual(core.read_json(self.root/"installation.json")["current"],"0.1.1")
        self.assertEqual((self.root/core.BOOT).read_bytes(),b"new boot")
        core.confirm(self.root)
        self.assertFalse(core.read_json(self.root/"installation.json")["pending"])
        self.assertEqual((self.root/"userdata/identity.json").read_text(),'keep identity')

    def test_pending_recovery(self):
        package,_,_=self.package()
        core.stage(self.root,package,self.public);core.apply(self.root,self.public);core.recover(self.root)
        self.assertEqual(core.read_json(self.root/"installation.json")["current"],"0.1.0")
        self.assertEqual((self.root/core.BOOT).read_bytes(),b"old")

    def test_staged_tamper_rejected(self):
        package,_,_=self.package();core.stage(self.root,package,self.public)
        staged,_=core.staged_record(self.root,self.public)
        (staged/"program"/core.ENTRY).write_bytes(b"bad")
        with self.assertRaises(core.UpdateError):core.apply(self.root,self.public)

    def test_incompatible_save_preserved(self):
        directory=self.root/"userdata/products/maps";directory.mkdir(parents=True)
        (directory/"sample.json").write_text('{"format_version":99}')
        package,_,_=self.package()
        with self.assertRaises(core.UpdateError):core.stage(self.root,package,self.public)

    def test_active_lease_rejects(self):
        if core.os.name!="nt":return
        lease=self.root/"cache/sessions/active.lock"
        with core.exclusive(lease):
            with self.assertRaises(core.UpdateError):core.assert_idle(self.root)

if __name__=="__main__":unittest.main()
