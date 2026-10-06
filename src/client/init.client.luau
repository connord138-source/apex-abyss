--!strict
-- Client bootstrap. The client is presentation and its own fish's movement; the
-- server never trusts it for growth, eats or banking.
local ClientState = require(script.ClientState)

ClientState.start()

print("[ApexAbyss] Client ready")
