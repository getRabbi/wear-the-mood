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
@pytest.mark.parametrize("value", ["true", "True", "TRUE "])
def test_literal_true_starts(value: str) -> None:
    validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": value})


# CHANGED DELIBERATELY. `false` used to be accepted here, because the guard only
# asked whether the value was well-formed. That closed half the hole: `false` is a
# perfectly well-formed value producing exactly the outage the guard exists to
# prevent -- every device on the cloud worker, a healthy /healthz, a green deploy,
# and no evidence except a fallback rate nobody watches. Switching the feature off
# during an incident is a real need, so it now takes the emergency switch below,
# which is audited and visible, rather than a value that reads as ordinary config.
@pytest.mark.parametrize("value", ["false", "False", " false"])
def test_explicit_false_refuses_to_start_in_prod(value: str) -> None:
    with pytest.raises(RuntimeError) as excinfo:
        validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": value})
    message = str(excinfo.value)
    assert "disables local-first background removal for EVERY user" in message
    assert "LOCAL_CUTOUT_EMERGENCY_DISABLE=true" in message


def test_the_emergency_switch_permits_a_deliberate_outage() -> None:
    # An incident responder must be able to switch it off. The point is not to make
    # that impossible, it is to make it impossible to do SILENTLY.
    validate_production_gates(
        _settings("prod"),
        env={
            "LOCAL_CUTOUT_UPLOAD_ENABLED": "false",
            "LOCAL_CUTOUT_EMERGENCY_DISABLE": "true",
        },
    )


def test_the_emergency_switch_is_audit_logged_every_boot(
    caplog: pytest.LogCaptureFixture,
) -> None:
    # For as long as it is engaged, every worker says so on every start. A
    # kill-switch left on and forgotten is the same outage it was meant to contain.
    with caplog.at_level("WARNING"):
        validate_production_gates(
            _settings("prod"),
            env={
                "LOCAL_CUTOUT_UPLOAD_ENABLED": "false",
                "LOCAL_CUTOUT_EMERGENCY_DISABLE": "true",
            },
        )
    assert any("AUDIT LOCAL_CUTOUT_EMERGENCY_DISABLE=true" in r.message for r in caplog.records)


def test_a_malformed_emergency_switch_refuses_to_start() -> None:
    with pytest.raises(RuntimeError) as excinfo:
        validate_production_gates(
            _settings("prod"),
            env={
                "LOCAL_CUTOUT_UPLOAD_ENABLED": "true",
                "LOCAL_CUTOUT_EMERGENCY_DISABLE": "maybe",
            },
        )
    assert "LOCAL_CUTOUT_EMERGENCY_DISABLE" in str(excinfo.value)


def test_the_emergency_switch_defaults_off_when_absent() -> None:
    # Absent means normal operation, so an ordinary deploy needs no new variable --
    # but it also means `false` for the ingestion gate stays a startup failure.
    validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": "true"})
    with pytest.raises(RuntimeError):
        validate_production_gates(_settings("prod"), env={"LOCAL_CUTOUT_UPLOAD_ENABLED": "false"})


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


class TestOperatorVisibleHealth:
    """/readyz must name the local-cutout state (§2.3).

    "ready" alone was never enough: the deploy that dropped the gate answered 200
    here while every device silently reverted to the BiRefNet worker.
    """

    def test_enabled_when_the_gate_and_storage_are_both_on(self) -> None:
        settings = Settings(
            environment="prod",
            local_cutout_upload_enabled=True,
            storage_writes="r2",
            r2_endpoint="https://example.r2.cloudflarestorage.com",
            r2_access_key_id="key",
            r2_secret_access_key="secret",
            r2_public_base_url="https://cdn.example.com",
        )
        assert settings.local_cutout_health == "enabled"
        assert settings.local_cutout_available is True

    def test_gate_off_is_named(self) -> None:
        settings = Settings(environment="prod", local_cutout_upload_enabled=False)
        assert settings.local_cutout_health == "gate_off"
        assert settings.local_cutout_available is False

    def test_the_emergency_state_is_distinguishable_from_the_gate(self) -> None:
        # Different investigations entirely: one is "this build never had it", the
        # other is "we switched it off ten minutes ago".
        settings = Settings(
            environment="prod",
            local_cutout_upload_enabled=True,
            local_cutout_emergency_disable=True,
        )
        assert settings.local_cutout_health == "emergency_disabled"
        assert settings.local_cutout_available is False

    def test_missing_storage_is_named_separately(self) -> None:
        settings = Settings(environment="prod", local_cutout_upload_enabled=True)
        assert settings.local_cutout_health == "storage_unavailable"
