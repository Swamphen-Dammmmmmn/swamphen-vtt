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
    def test_retry_uses_saved_packages_but_not_missing_or_expired_ones(self):
        saved=[{'name':'release-packages','expired':False}]
        self.assertEqual(ci.select_reuse('',2,saved,'123'),'123')
        self.assertEqual(ci.select_reuse('',1,saved,'123'),'')
        self.assertEqual(ci.select_reuse('',2,[],'123'),'')
        self.assertEqual(ci.select_reuse('',2,[{'name':'release-packages','expired':True}],'123'),'')
        self.assertEqual(ci.select_reuse('456',1,[],'123'),'456')
        with self.assertRaises(RuntimeError): ci.select_reuse('not-an-id',2,saved,'123')

    def test_recovery_refuses_foreign_workflow_and_invalid_source(self):
        valid={'path':'.github/workflows/release.yml','head_branch':'main','event':'workflow_dispatch','head_sha':'a'*40}
        self.assertEqual(ci.trusted_run_source(valid),'a'*40)
        for key,value in [('path','another.yml'),('head_branch','untrusted'),('event','pull_request'),('head_sha','bad')]:
            with self.subTest(key=key), self.assertRaises(RuntimeError): ci.trusted_run_source(dict(valid,**{key:value}))

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
