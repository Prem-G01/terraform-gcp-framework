output "keyrings" {

  value = {

    for k, v in google_kms_key_ring.keyring :

    k => v.id

  }

}



output "crypto_keys" {

  value = {

    for k, v in google_kms_crypto_key.crypto_key :

    k => v.id

  }

}