-- Atomically repoint current to a retained immutable Runtime Snapshot version.
-- KEYS[1] runtime-snapshot:{tenant_id}:version:<target_version>
-- KEYS[2] runtime-snapshot:{tenant_id}:current
-- KEYS[3] runtime-snapshot:{tenant_id}:notifications
-- ARGV: expected_current_version, target_version, tenant_id, activated_at, notification_id

local function response(ok, reason_code, fields)
  local result = fields or {}
  result.ok = ok
  result.reason_code = reason_code
  return cjson.encode(result)
end

local function key_type(key)
  return redis.call("TYPE", key).ok
end

local function is_positive_integer(value)
  return type(value) == "string" and string.match(value, "^[1-9][0-9]*$") ~= nil
end

local function compare_versions(left, right)
  if string.len(left) ~= string.len(right) then
    return string.len(left) < string.len(right) and -1 or 1
  end
  if left == right then
    return 0
  end
  return left < right and -1 or 1
end

if #KEYS ~= 3 or #ARGV ~= 5 then
  return response(false, "SNAPSHOT_ARGUMENT_CONTRACT_INVALID")
end

local expected_current_version = ARGV[1]
local target_version = ARGV[2]
local tenant_id = ARGV[3]
local activated_at = ARGV[4]
local notification_id = ARGV[5]

if tenant_id == "" or string.find(tenant_id, "[{}]") then
  return response(false, "SNAPSHOT_TENANT_INVALID", { tenant_id = tenant_id })
end
if not is_positive_integer(expected_current_version) or not is_positive_integer(target_version) then
  return response(false, "SNAPSHOT_VERSION_INVALID", { tenant_id = tenant_id, config_version = target_version })
end
if activated_at == "" or notification_id == "" then
  return response(false, "SNAPSHOT_PUBLICATION_METADATA_INVALID", { tenant_id = tenant_id, config_version = target_version })
end
if KEYS[1] ~= "runtime-snapshot:{" .. tenant_id .. "}:version:" .. target_version or
  KEYS[2] ~= "runtime-snapshot:{" .. tenant_id .. "}:current" or
  KEYS[3] ~= "runtime-snapshot:{" .. tenant_id .. "}:notifications" then
  return response(false, "SNAPSHOT_TENANT_KEY_MISMATCH", { tenant_id = tenant_id, config_version = target_version })
end

local target_type = key_type(KEYS[1])
local current_type = key_type(KEYS[2])
local notification_type = key_type(KEYS[3])
if target_type == "none" then
  return response(false, "SNAPSHOT_ROLLBACK_TARGET_MISSING", { tenant_id = tenant_id, config_version = target_version })
end
if target_type ~= "hash" or current_type ~= "hash" or
  (notification_type ~= "none" and notification_type ~= "stream") then
  return response(false, "SNAPSHOT_KEY_TYPE_INVALID", { tenant_id = tenant_id, config_version = target_version })
end

local current_version = redis.call("HGET", KEYS[2], "config_version") or ""
if current_version == target_version then
  return response(true, "SNAPSHOT_ALREADY_CURRENT", { tenant_id = tenant_id, config_version = target_version })
end
if current_version ~= expected_current_version then
  return response(false, "SNAPSHOT_CURRENT_VERSION_CONFLICT", {
    tenant_id = tenant_id,
    config_version = target_version,
    current_version = current_version
  })
end
if compare_versions(target_version, current_version) >= 0 then
  return response(false, "SNAPSHOT_ROLLBACK_TARGET_NOT_OLDER", {
    tenant_id = tenant_id,
    config_version = target_version,
    current_version = current_version
  })
end

local snapshot_json = redis.call("HGET", KEYS[1], "snapshot_json")
local content_hash = redis.call("HGET", KEYS[1], "content_hash")
local effective_at = redis.call("HGET", KEYS[1], "effective_at")
if not snapshot_json or not content_hash or not effective_at then
  return response(false, "SNAPSHOT_ROLLBACK_TARGET_INVALID", { tenant_id = tenant_id, config_version = target_version })
end

redis.call("XADD", KEYS[3], "*",
  "schema_version", "1",
  "notification_id", notification_id,
  "tenant_id", tenant_id,
  "config_version", target_version,
  "content_hash", content_hash,
  "activated_at", activated_at,
  "transition_reason", "ROLLBACK")

-- Keep the current pointer as the final write. Consumers confirm it before swap,
-- so an orphan rollback notification cannot activate a partial transition.
redis.call("HSET", KEYS[2],
  "config_version", target_version,
  "tenant_id", tenant_id,
  "snapshot_json", snapshot_json,
  "content_hash", content_hash,
  "effective_at", effective_at,
  "rollback_revision", target_version,
  "activated_at", activated_at,
  "transition_reason", "ROLLBACK",
  "transitioned_from_version", current_version)

return response(true, "SNAPSHOT_ROLLED_BACK", {
  tenant_id = tenant_id,
  config_version = target_version,
  previous_version = current_version,
  notification_id = notification_id
})
