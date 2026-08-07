-- Read the current Runtime Snapshot pointer for one tenant.
-- KEYS[1] runtime-snapshot:{tenant_id}:current
-- ARGV[1] tenant_id

local function response(ok, reason_code, fields)
  local result = fields or {}
  result.ok = ok
  result.reason_code = reason_code
  return cjson.encode(result)
end

local function hash_to_object(values)
  local result = {}
  for index = 1, #values, 2 do
    result[values[index]] = values[index + 1]
  end
  return result
end

if #KEYS ~= 1 or #ARGV ~= 1 then
  return response(false, "SNAPSHOT_ARGUMENT_CONTRACT_INVALID")
end

local tenant_id = ARGV[1]
if tenant_id == "" or string.find(tenant_id, "[{}]") then
  return response(false, "SNAPSHOT_TENANT_INVALID", { tenant_id = tenant_id })
end
if KEYS[1] ~= "runtime-snapshot:{" .. tenant_id .. "}:current" then
  return response(false, "SNAPSHOT_TENANT_KEY_MISMATCH", { tenant_id = tenant_id })
end

local key_type = redis.call("TYPE", KEYS[1]).ok
if key_type == "none" then
  return response(true, "SNAPSHOT_CURRENT_MISSING", { tenant_id = tenant_id, found = false })
end
if key_type ~= "hash" then
  return response(false, "SNAPSHOT_KEY_TYPE_INVALID", { tenant_id = tenant_id })
end

return response(true, "SNAPSHOT_CURRENT_READ", {
  tenant_id = tenant_id,
  found = true,
  snapshot = hash_to_object(redis.call("HGETALL", KEYS[1]))
})
