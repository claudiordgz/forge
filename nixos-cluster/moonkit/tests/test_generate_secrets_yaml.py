import pytest
from pathlib import Path
from unittest.mock import patch, mock_open
from moonkit import generate_secrets_yaml as gen

DUMMY_KEY = "ssh-ed25519 AAAADUMMYKEY comment"

@pytest.fixture
def fake_keys():
    return {
        f"{node}-{key_type}.pub": DUMMY_KEY
        for node in gen.NODES
        for key_type in gen.KEY_TYPES
    }

def test_read_key_reads_file_correctly(fake_keys):
    with patch("pathlib.Path.exists", return_value=True), \
         patch("pathlib.Path.read_text", return_value=DUMMY_KEY):
        key = gen.read_key("vega", "github")
        assert key == DUMMY_KEY

def test_generate_secrets_builds_full_structure(fake_keys):
    def fake_exists(path):
        return True

    def fake_read_text(self):
        return DUMMY_KEY

    with patch("pathlib.Path.exists", fake_exists), \
         patch("pathlib.Path.read_text", fake_read_text):
        secrets = gen.generate_secrets()

    assert set(secrets["sshKeys"].keys()) == set(gen.NODES)
    for node in gen.NODES:
        for key_type in gen.KEY_TYPES:
            assert secrets["sshKeys"][node][key_type] == DUMMY_KEY