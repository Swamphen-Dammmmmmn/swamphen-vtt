extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")
static var PATH := StoragePaths.data_path("network.cfg")
const DEFAULT_ADDRESS := "wss://154.12.41.6:10130"
const DEFAULT_CERTIFICATE := "res://assets/network/default.crt"

static func read() -> Dictionary:
	var file := ConfigFile.new()
	file.load(PATH)
	var certificate := str(file.get_value("relay","certificate",DEFAULT_CERTIFICATE))
	if not certificate.begins_with("res://") and not certificate.begins_with("certificates/"):
		var imported := StoragePaths.import_certificate(certificate)
		if not imported.is_empty():
			certificate = imported
			file.set_value("relay","certificate",certificate)
			file.save(PATH)
	return {"address":str(file.get_value("relay","address",DEFAULT_ADDRESS)),"certificate":StoragePaths.certificate_path(certificate)}

static func save(address: String, certificate: String) -> Error:
	if not address.begins_with("wss://") or address.length()>512: return ERR_INVALID_PARAMETER
	var chain := X509Certificate.new()
	if chain.load(certificate)!=OK: return ERR_INVALID_DATA
	var stored := StoragePaths.import_certificate(certificate)
	if stored.is_empty(): return ERR_CANT_CREATE
	var file := ConfigFile.new()
	file.set_value("relay","address",address.strip_edges())
	file.set_value("relay","certificate",stored)
	return file.save(PATH)
