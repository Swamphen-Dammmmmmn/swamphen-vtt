"""File transaction tests with synthetic payloads. Never starts Godot."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import io
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

    def github_fixture(self, prerelease=False):
        archive,_,_=self.package()
        with zipfile.ZipFile(archive) as package:record=json.loads(package.read("release.json"))
        base="https://github.com/"+core.REPOSITORY+"/releases/download/v0.1.1/"
        record.update(url=base+"update.zip",package_size=archive.stat().st_size,package_sha256=core.sha(archive))
        raw=json.dumps(record).encode()
        signature=base64.b64encode(self.key.sign(raw,padding.PSS(mgf=padding.MGF1(hashes.SHA256()),salt_length=padding.PSS.DIGEST_LENGTH),hashes.SHA256()))
        assets=[{"name":name,"state":"uploaded","browser_download_url":base+name,"size":len(value)} for name,value in [("release.json",raw),("release.sig",signature),("update.zip",archive.read_bytes())]]
        release={"tag_name":"v0.1.1","draft":False,"prerelease":prerelease,"assets":assets}
        def fetch(url,certificate,limit):
            if url==core.RELEASE_API:return json.dumps([release]).encode()
            return raw if url.endswith("release.json") else signature
        return archive,record,release,fetch

    def test_testing_channel_recognizes_prerelease(self):
        _,_,_,fetch=self.github_fixture(True)
        layout=core.read_json(self.root/"installation.json")
        core.atomic_json(self.root/"installation.json",dict(layout,channel="testing"))
        with patch.object(core,"fetch",side_effect=fetch):
            self.assertEqual(core.check(self.root,self.public,None)[0]["version"],"0.1.1")

    def test_stable_channel_excludes_prerelease(self):
        _,_,_,fetch=self.github_fixture(True)
        with patch.object(core,"fetch",side_effect=fetch),self.assertRaises(core.UpdateError):core.check(self.root,self.public,None)

    def test_github_asset_mismatch_rejected(self):
        _,_,release,fetch=self.github_fixture()
        release["assets"][-1]["size"]+=1
        with patch.object(core,"fetch",side_effect=fetch),self.assertRaises(core.UpdateError):core.check(self.root,self.public,None)

    def test_download_bytes_and_verification_separate(self):
        archive,record,_,_=self.github_fixture()
        stream=io.BytesIO(archive.read_bytes())
        stream.url=record["url"]
        events=[]
        with patch.object(core.urllib.request,"urlopen",return_value=stream):
            result=core.download(self.root,record,self.public,None,events.append)
        self.assertEqual(result["version"],"0.1.1")
        completed=[event for event in events if event["phase"]=="download"][-1]
        self.assertEqual(completed["downloaded"],archive.stat().st_size)
        self.assertEqual(completed["progress"],1)
        self.assertTrue(any(event["phase"]=="verify" for event in events))
        self.assertEqual((self.root/"userdata"/"identity.json").read_text(),"keep identity")

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
