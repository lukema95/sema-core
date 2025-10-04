module aas::resolver_dispatcher {
    use std::option::{Self, Option};
    use std::string; 
    use std::signer;
    use aptos_std::bcs;

    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::function_info::{Self, FunctionInfo};
    use aptos_framework::fungible_asset;
    use aptos_framework::object;

    use aas::package_manager;
    use aas::resolver_storage;

    const VERIFY_SUCCESS: u128 = 0;
    const VERIFY_FAILURE: u128 = 1;

    public fun on_attest(
      module_address: address,
      attestor: address,
      recipient: address,
      schema_address: address,
      ref_attestation: address,
      expiration_time: u64,
      revokable: bool,
      data: vector<u8>
    ): bool {
      if (resolver_storage::dispatcher_is_exists(module_address)) {
          let data = resolver_storage::pack_attest_data(attestor, recipient, schema_address, ref_attestation, expiration_time, revokable, data);
          resolver_storage::insert(module_address, data);
          
          let result = dispatch(module_address);
          if (option::is_some(&result)) {
            return *option::borrow(&result) == VERIFY_SUCCESS
          };
          return false
      };

      true
    }

    public fun on_revoke(
      module_address: address,
      revoker: address,
      schema_address: address,
      attestation: address,
    ): bool {
      if (resolver_storage::dispatcher_is_exists(module_address)) {
        let data = resolver_storage::pack_revoke_data(revoker, schema_address, attestation);
        resolver_storage::insert(module_address, data);

        let result = dispatch(module_address);
        if (option::is_some(&result)) {
          return *option::borrow(&result) == VERIFY_SUCCESS
        };

        return false
      };

      true
    }

    /// Register the dispatchable function of the dispatcher.
    public fun register_dispatchable(signer: &signer) {
        let cb = function_info::new_function_info(
            signer,
            string::utf8(b"schema_resolver"),
            string::utf8(b"resolve"),
        );

        let signer_address = signer::address_of(signer);

        register(cb, signer_address)
    }

    fun register(callback: FunctionInfo, signer_address: address) {
        let constructor_ref = object::create_named_object(&package_manager::get_signer(), bcs::to_bytes(&signer_address));
        let metadata = fungible_asset::add_fungibility(
            &constructor_ref,
            option::none(),
            string::utf8(b"resolver"),
            string::utf8(b"dispatch"),
            0,
            string::utf8(b""),
            string::utf8(b""),
        );
        dispatchable_fungible_asset::register_derive_supply_dispatch_function(
            &constructor_ref,
            option::some(callback),
        );

        resolver_storage::set_dispatcher_metadata(signer_address, metadata);
    }

    fun dispatch(signer_address: address): Option<u128> {
      let metadata = resolver_storage::dispatcher_metadata(signer_address);
      dispatchable_fungible_asset::derived_supply(metadata)
    }
}