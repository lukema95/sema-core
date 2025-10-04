module resolver_example::schema_resolver {
  use std::option;
  use std::string;
  use std::vector;
  use std::error;
  use std::from_bcs;
  use std::debug;
  use aptos_framework::object::{Object};

  use aas::resolver_dispatcher;
  use aas::resolver_storage;

  const EINVALID_ARGUMENT: u64 = 0;

  const RESOLVE_ATTEST_TYPE: u8 = 0;
  const RESOLVE_REVOKE_TYPE: u8 = 1;

  fun init_module(publisher: &signer) {
    register(publisher);
  }

  fun register(publisher: &signer) {
    resolver_dispatcher::register_dispatchable(publisher);
  }

  public fun resolve<T: key>(_metadata: Object<T>): option::Option<u128> {
    debug::print(&string::utf8(b"enter resolver_example::schema_resolver::resolve"));
    let data = resolver_storage::retrieve(@resolver_example);
    let resolve_type = from_bcs::to_u8(vector::slice(&data, 0, 1));
    if (resolve_type == RESOLVE_ATTEST_TYPE) {
      return resolve_attest(data)
    } else if (resolve_type == RESOLVE_REVOKE_TYPE) {
      return resolve_revoke(data)
    };

    option::none()
  }

  fun resolve_attest(data: vector<u8>): option::Option<u128> {
    let (_attestor, _recipient, _schema_address, _ref_attestation, _expiration_time, revokable, _data) = resolver_storage::unpack_attest_data(data);
    // assert!(attestor == recipient, error::invalid_argument(EINVALID_ARGUMENT));
    // assert!(schema_address != @0x0, error::invalid_argument(EINVALID_ARGUMENT));
    // assert!(ref_attestation == @0x0, error::invalid_argument(EINVALID_ARGUMENT));
    // assert!(expiration_time > 0, error::invalid_argument(EINVALID_ARGUMENT));
    assert!(revokable, error::invalid_argument(EINVALID_ARGUMENT));
    // assert!(vector::length(&data) > 0, error::invalid_argument(EINVALID_ARGUMENT));

    option::some(0)
  }

  fun resolve_revoke(data: vector<u8>): option::Option<u128> {
    let (_revoker, schema_address, attestation) = resolver_storage::unpack_revoke_data(data);
    assert!(schema_address != @0x0, error::invalid_argument(EINVALID_ARGUMENT));
    assert!(attestation != @0x0, error::invalid_argument(EINVALID_ARGUMENT));
    // assert!(revoker == @0xcafe, error::invalid_argument(EINVALID_ARGUMENT));

    option::some(0)
  }

  #[test_only]
  public fun init_for_test(publisher: &signer) {
    init_module(publisher);
  }
}