from app import Greeter
import pytest


@pytest.fixture
def greeter_fixture():
    return Greeter()


def test_greeter_sayは必ずhelloを含んでいる(greeter_fixture):
    assert "hello" in greeter_fixture.say("fuga")
