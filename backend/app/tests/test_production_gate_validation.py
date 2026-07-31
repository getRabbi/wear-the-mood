"""Production feature gates must be explicit, not defaulted (2026-07-30).

`local_cutout_upload_enabled` defaults to False. In production that default is not
a safe fallback -- it turns POST /v1/wardrobe/local-cutout into a 404 and silently
reverts every Android user to the slow BiRefNet path, with a healthy /health, a
green deploy and nothing in the logs. These tests pin the fail-fast behaviour.
"""

import pytest

from app.core.config import Settings, validate_production_gates


def _settings(environment: str) -> Settings:
    return Settings(environment=environment)


def test_absent_gate_refuses_to_start_in_prod() -> None:
    with pytest.raises(RuntimeError) as excinfo:
        validate_production_gates(_settings("prod"), env={})
    assert "LOCAL_CUTOUT_UPLOAD_ENABLED is not set" in str(excinfo.value)


@pytest.mark.parametrize("value", ["1", "0", "yes", "no", "on", "off", "", "maybe"])
def test_non_literal_gate_refuses_to_start_in_prod(value: str) -> None:
    # Pydantic happily coerces 1/yes/on to True, so these WOULD boot -- but the
    # config would then mean something different to the app than to the human
    # reading it, which is the ambiguity this guard exists to remove.
    with pytest.raises(RuntimeError) as excinfo:
        validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": value})
    assert "not the literal" in str(excinfo.value)


# Case and surrounding whitespace are accepted: "TRUE " means exactly what it
# looks like, and refusing a deploy over a stray space would be pedantry, not
# safety.
@pytest.mark.parametrize("value", ["true", "false", "True", "FALSE", "TRUE ", " false"])
def test_literal_gate_starts(value: str) -> None:
    validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": value})


@pytest.mark.parametrize("environment", ["dev", "staging", "test"])
def test_non_prod_environments_are_untouched(environment: str) -> None:
    # A dev box must not need every production gate set.
    validate_production_gates(_settings(environment), env={})


def test_the_error_names_every_problem_at_once() -> None:
    # One restart should reveal the whole list, not the first item repeatedly.
    with pytest.raises(RuntimeError) as excinfo:
        validate_production_gates(_settings("prod"), env={})
    message = str(excinfo.value)
    assert "Refusing to start" in message
    assert "LOCAL_CUTOUT_UPLOAD_ENABLED" in message
