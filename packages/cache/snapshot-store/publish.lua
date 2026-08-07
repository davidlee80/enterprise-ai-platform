-- Atomically publish an immutable Runtime Snapshot and advance its current pointer.
-- KEYS[1] runtime-snapshot:{tenant_id}:version:<config_version>
-- KEYS[2] runtime-snapshot:{tenant_id}:current
-- KEYS[3] runtime-snapshot:{tenant_id}:notifications
-- ARGV: expected_current_version, config_version, tenant_id, snapshot_json,
--       content_hash, effective_at, rollback_revision, activated_at, notification_id

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

local function is_dense_string_array(value, allow_empty)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  local maximum = 0
  for key, item in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or type(item) ~= "string" or item == "" then
      return false
    end
    count = count + 1
    if key > maximum then
      maximum = key
    end
  end
  if count ~= maximum then
    return false
  end
  return allow_empty or count > 0
end

local function contains_sensitive_field(value)
  if type(value) ~= "table" then
    return false
  end
  for key, nested in pairs(value) do
    if type(key) == "string" then
      local field = string.lower(key)
      if field ~= "secret_ref" and (
        field == "secret" or
        field == "token" or
        field == "credential" or
        field == "credentials" or
        field == "api_key" or
        field == "provider_key" or
        string.match(field, "_token$") or
        string.match(field, "_api_key$")
      ) then
        return true
      end
    end
    if contains_sensitive_field(nested) then
      return true
    end
  end
  return false
end

if #KEYS ~= 3 or #ARGV ~= 9 then
  return response(false, "SNAPSHOT_ARGUMENT_CONTRACT_INVALID")
end

local expected_current_version = ARGV[1]
local config_version = ARGV[2]
local tenant_id = ARGV[3]
local snapshot_json = ARGV[4]
local content_hash = string.lower(ARGV[5])
local effective_at = ARGV[6]
local rollback_revision = ARGV[7]
local activated_at = ARGV[8]
local notification_id = ARGV[9]

if tenant_id == "" or string.find(tenant_id, "[{}]") then
  return response(false, "SNAPSHOT_TENANT_INVALID", { tenant_id = tenant_id })
end
if not is_positive_integer(config_version) then
  return response(false, "SNAPSHOT_VERSION_INVALID", { config_version = config_version })
end
if expected_current_version ~= "" and not is_positive_integer(expected_current_version) then
  return response(false, "SNAPSHOT_EXPECTED_VERSION_INVALID", { config_version = config_version })
end
if rollback_revision ~= "" and not is_positive_integer(rollback_revision) then
  return response(false, "SNAPSHOT_ROLLBACK_REVISION_INVALID", { config_version = config_version })
end
if not string.match(content_hash, "^[0-9a-f]+$") or string.len(content_hash) ~= 64 then
  return response(false, "SNAPSHOT_CONTENT_HASH_INVALID", { config_version = config_version })
end
if effective_at == "" or activated_at == "" or notification_id == "" then
  return response(false, "SNAPSHOT_PUBLICATION_METADATA_INVALID", { config_version = config_version })
end

local expected_version_key = "runtime-snapshot:{" .. tenant_id .. "}:version:" .. config_version
local expected_current_key = "runtime-snapshot:{" .. tenant_id .. "}:current"
local expected_notification_key = "runtime-snapshot:{" .. tenant_id .. "}:notifications"
if KEYS[1] ~= expected_version_key or KEYS[2] ~= expected_current_key or KEYS[3] ~= expected_notification_key then
  return response(false, "SNAPSHOT_TENANT_KEY_MISMATCH", { tenant_id = tenant_id, config_version = config_version })
end

local version_type = key_type(KEYS[1])
local current_type = key_type(KEYS[2])
local notification_type = key_type(KEYS[3])
if (version_type ~= "none" and version_type ~= "hash") or
  (current_type ~= "none" and current_type ~= "hash") or
  (notification_type ~= "none" and notification_type ~= "stream") then
  return response(false, "SNAPSHOT_KEY_TYPE_INVALID", { tenant_id = tenant_id, config_version = config_version })
end

local decoded_ok, snapshot = pcall(cjson.decode, snapshot_json)
if not decoded_ok or type(snapshot) ~= "table" then
  return response(false, "SNAPSHOT_PAYLOAD_JSON_INVALID", { tenant_id = tenant_id, config_version = config_version })
end
if type(snapshot.config_version) ~= "number" or snapshot.config_version ~= tonumber(config_version) or snapshot.config_version < 1 or snapshot.config_version ~= math.floor(snapshot.config_version) then
  return response(false, "SNAPSHOT_PAYLOAD_VERSION_MISMATCH", { tenant_id = tenant_id, config_version = config_version })
end
if type(snapshot.tenant_id) ~= "string" or snapshot.tenant_id ~= tenant_id then
  return response(false, "SNAPSHOT_PAYLOAD_TENANT_MISMATCH", { tenant_id = tenant_id, config_version = config_version })
end
if type(snapshot.model_alias) ~= "string" or snapshot.model_alias == "" or
  type(snapshot.route_strategy) ~= "string" or snapshot.route_strategy == "" or
  not is_dense_string_array(snapshot.policy_ids, true) or
  not is_dense_string_array(snapshot.providers, false) then
  return response(false, "SNAPSHOT_CORE_FIELDS_INVALID", { tenant_id = tenant_id, config_version = config_version })
end
if contains_sensitive_field(snapshot) then
  return response(false, "SNAPSHOT_PLAINTEXT_CREDENTIAL_FIELD_FORBIDDEN", { tenant_id = tenant_id, config_version = config_version })
end

local stored_payload = redis.call("HGET", KEYS[1], "snapshot_json")
local stored_hash = redis.call("HGET", KEYS[1], "content_hash")
if version_type == "hash" and not stored_payload then
  return response(false, "SNAPSHOT_VERSION_INVALID", { tenant_id = tenant_id, config_version = config_version })
end
if stored_payload and (
  stored_payload ~= snapshot_json or
  stored_hash ~= content_hash or
  redis.call("HGET", KEYS[1], "tenant_id") ~= tenant_id or
  redis.call("HGET", KEYS[1], "config_version") ~= config_version or
  redis.call("HGET", KEYS[1], "effective_at") ~= effective_at or
  redis.call("HGET", KEYS[1], "rollback_revision") ~= rollback_revision
) then
  return response(false, "SNAPSHOT_VERSION_CONFLICT", { tenant_id = tenant_id, config_version = config_version })
end

local current_version = redis.call("HGET", KEYS[2], "config_version") or ""
if current_type == "hash" and current_version == "" then
  return response(false, "SNAPSHOT_CURRENT_POINTER_INVALID", { tenant_id = tenant_id, config_version = config_version })
end
if current_version == config_version and stored_payload then
  return response(true, "SNAPSHOT_ALREADY_CURRENT", { tenant_id = tenant_id, config_version = config_version })
end
if current_version ~= expected_current_version then
  return response(false, "SNAPSHOT_CURRENT_VERSION_CONFLICT", {
    tenant_id = tenant_id,
    config_version = config_version,
    current_version = current_version
  })
end
if current_version ~= "" and compare_versions(config_version, current_version) <= 0 then
  return response(false, "SNAPSHOT_VERSION_NOT_NEWER", {
    tenant_id = tenant_id,
    config_version = config_version,
    current_version = current_version
  })
end

if not stored_payload then
  redis.call("HSET", KEYS[1],
    "config_version", config_version,
    "tenant_id", tenant_id,
    "snapshot_json", snapshot_json,
    "content_hash", content_hash,
    "effective_at", effective_at,
    "rollback_revision", rollback_revision,
    "published_at", activated_at)
end

redis.call("XADD", KEYS[3], "*",
  "schema_version", "1",
  "notification_id", notification_id,
  "tenant_id", tenant_id,
  "config_version", config_version,
  "content_hash", content_hash,
  "activated_at", activated_at,
  "transition_reason", "PUBLISH")

-- Keep the current pointer as the final write. Consumers confirm it before swap,
-- so an orphan version/notification from an unexpected earlier command failure
-- cannot activate a partially published candidate.
redis.call("HSET", KEYS[2],
  "config_version", config_version,
  "tenant_id", tenant_id,
  "snapshot_json", snapshot_json,
  "content_hash", content_hash,
  "effective_at", effective_at,
  "rollback_revision", rollback_revision,
  "activated_at", activated_at,
  "transition_reason", "PUBLISH",
  "transitioned_from_version", current_version)

return response(true, "SNAPSHOT_PUBLISHED", {
  tenant_id = tenant_id,
  config_version = config_version,
  previous_version = current_version,
  notification_id = notification_id
})
