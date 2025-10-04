module aas::resolver_storage {
    use std::bcs;
    use std::from_bcs;
    use std::vector;

    use aptos_framework::table::{Self, Table};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::object::{Object};

    use aas::package_manager;

    friend aas::resolver_dispatcher;

    const RESOLVE_ATTEST_TYPE: u8 = 0;
    const RESOLVE_REVOKE_TYPE: u8 = 1;

    const E_DISPATCHER_NOT_FOUND: u64 = 1;
    
    /// The dispatcher table to store the metadata of the dispatcher 
    /// and the data associated with the module address.
    struct Dispatcher has key {
        /// The dispatcher table to store the metadata of the dispatcher.
        dispatcher: Table<address, Object<Metadata>>,
        /// The data table to store the data associated with the module address.
        data: Table<address, vector<u8>>,
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        let account = &package_manager::get_signer();
        
        move_to(account, Dispatcher {
            dispatcher: table::new(),
            data: table::new(),
        });
    }

    #[view]
    public fun is_initialized(): bool {
        exists<Dispatcher>(package_manager::get_signer_address())
    }

    /// Retrieves the data associated with the given module address.
    /// This function call by the outside module.
    public fun retrieve(module_address: address): vector<u8> acquires Dispatcher {
        let dispatcher = borrow_global<Dispatcher>(package_manager::get_signer_address());
        assert!(table::contains(&dispatcher.data, module_address), E_DISPATCHER_NOT_FOUND);
        *table::borrow(&dispatcher.data, module_address)
    }

    /// Inserts the data associated with the given module address.
    /// This function only call by the dispatcher.
    public(friend) fun insert(module_address: address, data: vector<u8>) acquires Dispatcher {
        let dispatcher = borrow_global_mut<Dispatcher>(package_manager::get_signer_address());
        table::upsert(&mut dispatcher.data, module_address, data);
    }

    /// Sets the metadata of the dispatcher.
    /// This function only call by the dispatcher.
    public(friend) fun set_dispatcher_metadata(module_address: address, metadata: Object<Metadata>) acquires Dispatcher {
        let dispatcher = borrow_global_mut<Dispatcher>(package_manager::get_signer_address());
        table::add(&mut dispatcher.dispatcher, module_address, metadata);
    }

    #[view]
    public fun dispatcher_metadata(signer_address: address): Object<Metadata> acquires Dispatcher {
        let dispatcher = borrow_global<Dispatcher>(package_manager::get_signer_address());
        assert!(table::contains(&dispatcher.dispatcher, signer_address), E_DISPATCHER_NOT_FOUND);
        *table::borrow(&dispatcher.dispatcher, signer_address)
    }

    #[view]
    public fun dispatcher_is_exists(signer_address: address): bool acquires Dispatcher {
        let dispatcher = borrow_global<Dispatcher>(package_manager::get_signer_address());
        table::contains(&dispatcher.dispatcher, signer_address)
    }

    #[view]
    public fun pack_attest_data(
      attestor: address,
      recipient: address,
      schema_address: address,
      ref_attestation: address,
      expiration_time: u64,
      revokable: bool,
      data: vector<u8>
    ): vector<u8> {
      let packed_data = vector::empty<u8>();
      vector::append(&mut packed_data, bcs::to_bytes(&RESOLVE_ATTEST_TYPE));
      vector::append(&mut packed_data, bcs::to_bytes(&attestor));
      vector::append(&mut packed_data, bcs::to_bytes(&recipient));
      vector::append(&mut packed_data, bcs::to_bytes(&schema_address));
      vector::append(&mut packed_data, bcs::to_bytes(&ref_attestation));
      vector::append(&mut packed_data, bcs::to_bytes(&expiration_time));
      vector::append(&mut packed_data, bcs::to_bytes(&revokable));
      vector::append(&mut packed_data, data);

      packed_data
    }

    #[view]
    public fun pack_revoke_data(
      revoker: address,
      schema_address: address,
      attestation: address,
    ): vector<u8> {
      let packed_data = vector::empty<u8>();
      vector::append(&mut packed_data, bcs::to_bytes(&RESOLVE_REVOKE_TYPE));
      vector::append(&mut packed_data, bcs::to_bytes(&revoker));
      vector::append(&mut packed_data, bcs::to_bytes(&schema_address));
      vector::append(&mut packed_data, bcs::to_bytes(&attestation));

      packed_data
    }

    #[view]
    public fun unpack_attest_data(data: vector<u8>): (address, address, address, address, u64, bool, vector<u8>) {
      let attestor = from_bcs::to_address(vector::slice(&data, 1, 33));
      let recipient = from_bcs::to_address(vector::slice(&data, 33, 65));
      let schema_address = from_bcs::to_address(vector::slice(&data, 65, 97));
      let ref_attestation = from_bcs::to_address(vector::slice(&data, 97, 129));
      let expiration_time = from_bcs::to_u64(vector::slice(&data, 129, 137));
      let revokable = from_bcs::to_bool(vector::slice(&data, 137, 138));
      let data = vector::slice(&data, 138, vector::length(&data));

      (attestor, recipient, schema_address, ref_attestation, expiration_time, revokable, data)
    }

    #[view]
    public fun unpack_revoke_data(data: vector<u8>): (address, address, address) {
      let revoker = from_bcs::to_address(vector::slice(&data, 1, 33));
      let schema_address = from_bcs::to_address(vector::slice(&data, 33, 65));
      let attestation = from_bcs::to_address(vector::slice(&data, 65, 97));

      (revoker, schema_address, attestation)
    }
}