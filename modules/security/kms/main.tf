locals {

  kms_keys = flatten([

    for kr_name, kr in var.config.kms : [

      for key_name, key in kr.keys : {

        keyring_key = kr_name

        location = kr.location

        key_name = key_name

        purpose = lookup(
          key,
          "purpose",
          "ENCRYPT_DECRYPT"
        )

        rotation_period = lookup(
          key,
          "rotation_period",
          "7776000s"
        )

      }

    ]

  ])



  kms_keys_map = {

    for k in local.kms_keys :

    "${k.keyring_key}-${k.key_name}" => k

  }

}



resource "google_kms_key_ring" "keyring" {

  for_each = var.config.kms



  project = var.project_id



  name = lookup(each.value, "name", each.key)



  location = each.value.location

}



resource "google_kms_crypto_key" "crypto_key" {

  for_each = local.kms_keys_map



  name = each.value.key_name



  key_ring = google_kms_key_ring.keyring[

    each.value.keyring_key

  ].id



  purpose = each.value.purpose



  rotation_period = each.value.rotation_period



  lifecycle {

    # Crypto keys must never be silently destroyed — anything encrypted
    # with this key becomes permanently unrecoverable. Run
    # `terraform state rm` deliberately (never `terraform destroy`) if a
    # key genuinely needs to go away.
    #
    # Was briefly set to false on 2026-08-18 and again on 2026-08-19 for
    # full, explicitly-requested teardowns of the dev environment (see
    # docs/troubleshooting.md) — restored immediately afterward both
    # times. GCP has no API to hard-delete a KMS key or keyring
    # regardless; that teardown only removed them from Terraform state,
    # it did not and could not delete the real keyring/keys.
    prevent_destroy = true

  }

}