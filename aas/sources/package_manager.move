module aas::package_manager {
    use aptos_framework::object::{Self, ExtendRef};
    use aptos_std::table::{Self, Table};
    use std::string::String;
    use std::signer;

    friend aas::schema;
    friend aas::attestation;
    friend aas::aas;
    friend aas::resolver_storage;
    friend aas::resolver_dispatcher;

    /// Stores permission config such as ExtendRef for controlling the object.
    struct PermissionConfig has key {
        /// Required to obtain the object signer.
        extend_ref: ExtendRef,
        /// Track the addresses created by the modules in this package.
        addressess: Table<String, address>
    }

    /// Initialize the module
    /// This function should only be called once when the package is published.
    fun init_module(signer: &signer) {
        let construct_ref = object::create_object(signer::address_of(signer));
        let extend_ref = object::generate_extend_ref(&construct_ref);
        move_to(signer, PermissionConfig {
            extend_ref,
            addressess: table::new()
        });
    }

    public(friend) fun get_signer(): signer acquires PermissionConfig {
      let extend_ref = &borrow_global<PermissionConfig>(@aas).extend_ref;
      object::generate_signer_for_extending(extend_ref)
    }

    public(friend) fun get_signer_address(): address acquires PermissionConfig {
      signer::address_of(&get_signer())
    }

    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
      let addressess = &mut borrow_global_mut<PermissionConfig>(@aas).addressess;
      table::upsert(addressess, name, object);
    }

    public fun address_exists(name: String): bool acquires PermissionConfig {
      let addressess = &borrow_global<PermissionConfig>(@aas).addressess;
      table::contains(addressess, name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
      let addressess = &borrow_global<PermissionConfig>(@aas).addressess;
      *table::borrow(addressess, name)
    }

    
    #[test_only]
    use aptos_framework::account;
    
    #[test_only]
    public fun initialize_for_test(resource_account: &signer) {
        let resource_account_address = signer::address_of(resource_account);
        if (!exists<PermissionConfig>(resource_account_address)) {
          aptos_framework::timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
          
          let construct_ref = object::create_named_object(resource_account, b"test");
          let extend_ref = object::generate_extend_ref(&construct_ref);
          
          account::create_account_for_test(resource_account_address);
          move_to(resource_account, PermissionConfig {
            extend_ref,
            addressess: table::new()
          });
        }
    }

    #[test_only]
    friend aas::aas_tests;
    #[test_only]
    friend aas::test_helpers;
}