"""File and command validation only; no game startup or network requests."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools'))
import ci_release as ci


class ReleaseChecks(unittest.TestCase):
    def test_version_and_platform_inputs(self):
        ci.validate('0.1.4','all',10401)
        ci.validate('0.1.3a','all',10312)
        for args in [('v0.1.4','all',0),('0.1.4;echo','all',0),('0.1.4','linux',0),('0.1.4','all',-1)]:
            with self.subTest(args=args), self.assertRaises(RuntimeError): ci.validate(*args)

    def test_private_source_is_rejected(self):
        for path in ['docs/plan.md','.agents/skills/skill/config.json','artifacts/private.pem','secret.keystore','nested/notes.md','userdata/token.json']:
            with self.subTest(path=path), patch.object(ci,'capture',return_value=path), self.assertRaises(RuntimeError):
                ci.public_source('HEAD')

    def test_public_source_is_allowed(self):
        with patch.object(ci,'capture',return_value='README.md\ntools/ci_release.py\n.github/workflows/release.yml\naddons/gohud/LICENSE.md'):
            ci.public_source('HEAD')

    def test_local_machine_cannot_use_ci_builder(self):
        with patch.dict(ci.os.environ,{'GITHUB_ACTIONS':'false'}), self.assertRaises(RuntimeError):
            ci.build(None)

    def test_apk_lock_preserves_existing_identity(self):
        self.assertEqual(ci.LOCK['package'],'org.swamphen.svtt.test')
        self.assertEqual(ci.LOCK['android_certificate_sha256'],'fc1d7b1535062c1a3caaa29b55a3f43f23f99450137748124a7a2e6bfa02c007')

    def test_public_release_cannot_be_replaced(self):
        with self.assertRaises(RuntimeError):
            ci.check_draft({'isDraft':False,'targetCommitish':'abc'},'abc')

    def test_draft_retry_requires_same_source(self):
        with self.assertRaises(RuntimeError):
            ci.check_draft({'isDraft':True,'targetCommitish':'old'},'new')
        ci.check_draft({'isDraft':True,'targetCommitish':'abc'},'abc')


if __name__=='__main__': unittest.main()
