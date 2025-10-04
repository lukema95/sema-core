#[test_only]
module sas::sas_tests {
    use std::string;
    use sui::{
        test_scenario::{Self},
        clock::{Self},
        hash,
    };
    use sas::sas::{Self};
    use sas::schema::{Self, Schema, ResolverBuilder};
    use sas::schema_registry::{Self, SchemaRegistry};
    use sas::attestation::{Self, Attestation};
    use sas::attestation_registry::{Self, AttestationRegistry};
    use sas::admin::{Admin};

    use fun string::utf8 as vector.utf8;

    const ENotImplemented: u64 = 0;
    const EAttestationNotFound: u64 = 1;

    public struct Witness has drop {}

    #[test]
    fun test_attest() {
        let admin: address = @0x1;
        let user: address = @0x2;

        let schema: vector<u8> = b"name: string, age: u64";
        let data: vector<u8> = b"alice, 100";
        let name: vector<u8> = b"Profile";
        let description: vector<u8> = b"Profile of a user";
        let url: vector<u8> = b"https://example.com";

        let attestation_address: address;

        // init
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        // make schema
        test_scenario::next_tx(&mut scenario, admin);
        {   
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let admin_cap = sas::register_schema(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                true, 
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };
        
        // make attestation
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            sas::attest(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                data,
                name,
                description,
                url,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };
        
        // check attestation is exist
        test_scenario::next_tx(&mut scenario, user);
        {
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            assert!(attestation::schema(&attestation) == schema_record.addy());
            attestation_address = object::id_address(&attestation);
            
            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        // revoke attestation
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let admin_cap = test_scenario::take_from_sender<Admin>(&scenario);
            sas::revoke(
                &admin_cap, 
                &mut attestation_registry, 
                &schema_record, 
                attestation_address, 
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Admin>(&scenario, admin_cap);
        };

        // check attestation is revoked
        test_scenario::next_tx(&mut scenario, user);
        {
            let attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            assert!(attestation_registry.is_revoked(attestation_address), EAttestationNotFound);

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_attest_with_resolver() {
        let admin: address = @0x1;
        let user: address = @0x2;
        let schema: vector<u8> = b"name: string, age: u64";
        let data: vector<u8> = b"alice, 100";
        let name: vector<u8> = b"Profile";
        let description: vector<u8> = b"Profile of a user";
        let url: vector<u8> = b"https://example.com";

        let mut resolver_builder: ResolverBuilder;
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let (builder, admin_cap, schema_record) = sas::register_schema_with_resolver(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                false, 
                test_scenario::ctx(&mut scenario)
            );
            schema_record.share_schema();

            resolver_builder = builder;
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };

        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);

            add_rule(&mut resolver_builder, schema::start_attest_name());

            schema_record.add_resolver(resolver_builder);

            let mut start_request = schema_record.start_attest();
            start_request.approve(Witness {});

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            sas::attest_with_resolver(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                data,
                name,
                description,
                url,
                &clock,
                start_request,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            assert!(attestation::schema(&attestation) == schema_record.addy());

            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        test_scenario::end(scenario);
    }

    fun add_rule(resolver_builder: &mut ResolverBuilder, name: vector<u8>) {
        resolver_builder.add_rule(name.utf8(), Witness {});
    }

    #[test]
    fun test_attest_off_chain() {
        let admin: address = @0x1;
        let user: address = @0x2;

        let schema: vector<u8> = b"name: string, age: u64";
        let name: vector<u8> = b"Profile";
        let description: vector<u8> = b"Profile of a user";
        let url: vector<u8> = b"https://example.com";

        // Simulate off-chain data (would be uploaded to Walrus in real scenario)
        let off_chain_data: vector<u8> = b"alice, 100";
        let walrus_sui_object_id: address = @0x1234567890abcdef1234567890abcdef12345678; // Mock Walrus Sui Object ID
        let walrus_blob_id: vector<u8> = b"base64url-blob-id-string"; // Mock Walrus blob ID (base64url string as bytes)
        let data_hash = hash::blake2b256(&off_chain_data); // Calculate data hash
        let encrypted = false;
        let seal_nonce: Option<vector<u8>> = option::none(); // Not encrypted, so no nonce
        let seal_policy_id: Option<address> = option::none();

        let attestation_address: address;

        // init
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        // make schema
        test_scenario::next_tx(&mut scenario, admin);
        {   
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let admin_cap = sas::register_schema(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                true, 
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };
        
        // make attestation with off-chain storage
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            sas::attest_off_chain(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                walrus_sui_object_id,
                walrus_blob_id,
                data_hash,
                encrypted,
                seal_nonce,
                seal_policy_id,
                name,
                description,
                url,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };
        
        // check attestation exists and verify off-chain storage fields
        test_scenario::next_tx(&mut scenario, user);
        {
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            
            // Verify basic fields
            assert!(attestation::schema(&attestation) == schema_record.addy(), 0);
            attestation_address = object::id_address(&attestation);
            
            // Verify storage type
            assert!(attestation::storage_type(&attestation) == 1, 0); // OFF_CHAIN = 1
            assert!(attestation::is_off_chain_storage(&attestation), 0);
            assert!(!attestation::is_on_chain_storage(&attestation), 0);
            
            // Verify off-chain storage fields
            let blob_id_opt = attestation::walrus_blob_id(&attestation);
            assert!(option::is_some(&blob_id_opt), 0);
            let stored_blob_id = *option::borrow(&blob_id_opt);
            assert!(stored_blob_id == walrus_blob_id, 0);
            
            // Verify Walrus Sui Object ID
            let sui_object_id_opt = attestation::walrus_sui_object_id(&attestation);
            assert!(option::is_some(&sui_object_id_opt), 0);
            let stored_sui_object_id = *option::borrow(&sui_object_id_opt);
            assert!(stored_sui_object_id == walrus_sui_object_id, 0);
            let hash_opt = attestation::data_hash(&attestation);
            assert!(option::is_some(&hash_opt), 0);
            let stored_hash = *option::borrow(&hash_opt);
            assert!(stored_hash == data_hash, 0);
            
            // Verify encryption status
            assert!(!attestation::is_encrypted(&attestation), 0);
            
            // Verify seal policy ID is none
            assert!(option::is_none(&attestation::seal_policy_id(&attestation)), 0);
            
            // Verify data() returns empty for off-chain storage
            let data = attestation::data(&attestation);
            assert!(vector::length(&data) == 0, 0);
            
            // Verify data integrity
            assert!(attestation::verify_data_integrity(&attestation, off_chain_data), 0);
            
            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        // revoke attestation
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let admin_cap = test_scenario::take_from_sender<Admin>(&scenario);
            sas::revoke(
                &admin_cap, 
                &mut attestation_registry, 
                &schema_record, 
                attestation_address, 
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Admin>(&scenario, admin_cap);
        };

        // check attestation is revoked
        test_scenario::next_tx(&mut scenario, user);
        {
            let attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            assert!(attestation_registry.is_revoked(attestation_address), EAttestationNotFound);

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_attest_off_chain_encrypted() {
        let admin: address = @0x1;
        let user: address = @0x2;

        let schema: vector<u8> = b"name: string, age: u64";
        let name: vector<u8> = b"Profile Encrypted";
        let description: vector<u8> = b"Profile of a user (encrypted)";
        let url: vector<u8> = b"https://example.com";

        // Simulate encrypted off-chain data
        let off_chain_data: vector<u8> = b"encrypted_data_here";
        let walrus_sui_object_id: address = @0xabcdef1234567890abcdef1234567890abcdef12; // Mock Walrus Sui Object ID
        let walrus_blob_id: vector<u8> = b"encrypted-base64url-blob-id"; // Mock Walrus blob ID (base64url string as bytes)
        let data_hash = hash::blake2b256(&off_chain_data); // Calculate data hash (of original data before encryption)
        let encrypted = true;
        let seal_nonce_bytes: vector<u8> = b"random-nonce-16b"; // Mock Seal nonce (16 bytes)
        let seal_nonce: Option<vector<u8>> = option::some(seal_nonce_bytes);
        let seal_policy_id: address = @0x9876543210fedcba9876543210fedcba98765432; // Mock Seal policy ID (optional, for other patterns)
        let seal_policy_id_opt: Option<address> = option::some(seal_policy_id);

        // init
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        // make schema
        test_scenario::next_tx(&mut scenario, admin);
        {   
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let admin_cap = sas::register_schema(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                true, 
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };
        
        // make attestation with encrypted off-chain storage
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            sas::attest_off_chain(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                walrus_sui_object_id,
                walrus_blob_id,
                data_hash,
                encrypted,
                seal_nonce,
                seal_policy_id_opt,
                name,
                description,
                url,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };
        
        // check attestation exists and verify encrypted off-chain storage fields
        test_scenario::next_tx(&mut scenario, user);
        {
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            
            // Verify basic fields
            assert!(attestation::schema(&attestation) == schema_record.addy(), 0);
            let _attestation_address = object::id_address(&attestation);
            
            // Verify storage type
            assert!(attestation::storage_type(&attestation) == 1, 0); // OFF_CHAIN = 1
            assert!(attestation::is_off_chain_storage(&attestation), 0);
            
            // Verify off-chain storage fields
            let blob_id_opt = attestation::walrus_blob_id(&attestation);
            assert!(option::is_some(&blob_id_opt), 0);
            let stored_blob_id = *option::borrow(&blob_id_opt);
            assert!(stored_blob_id == walrus_blob_id, 0);
            
            // Verify Walrus Sui Object ID
            let sui_object_id_opt = attestation::walrus_sui_object_id(&attestation);
            assert!(option::is_some(&sui_object_id_opt), 0);
            let stored_sui_object_id = *option::borrow(&sui_object_id_opt);
            assert!(stored_sui_object_id == walrus_sui_object_id, 0);
            let hash_opt = attestation::data_hash(&attestation);
            assert!(option::is_some(&hash_opt), 0);
            let stored_hash = *option::borrow(&hash_opt);
            assert!(stored_hash == data_hash, 0);
            
            // Verify encryption status
            assert!(attestation::is_encrypted(&attestation), 0);
            
            // Verify seal policy ID is set
            let policy_opt = attestation::seal_policy_id(&attestation);
            assert!(option::is_some(&policy_opt), 0);
            let stored_policy_id = *option::borrow(&policy_opt);
            assert!(stored_policy_id == seal_policy_id, 0);
            
            // Verify data() returns empty for off-chain storage
            let data = attestation::data(&attestation);
            assert!(vector::length(&data) == 0, 0);
            
            // Verify data integrity
            assert!(attestation::verify_data_integrity(&attestation, off_chain_data), 0);
            
            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_storage_type_functions() {
        let admin: address = @0x1;
        let user: address = @0x2;

        let schema: vector<u8> = b"name: string";
        let data: vector<u8> = b"alice";
        let name: vector<u8> = b"Test";
        let description: vector<u8> = b"Test";
        let url: vector<u8> = b"https://example.com";

        // init
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        // make schema
        test_scenario::next_tx(&mut scenario, admin);
        {   
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let admin_cap = sas::register_schema(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                true, 
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };
        
        // Test on-chain attestation
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            sas::attest(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                data,
                name,
                description,
                url,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };
        
        // Verify on-chain storage type functions
        test_scenario::next_tx(&mut scenario, user);
        {
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            
            // Verify storage type
            assert!(attestation::storage_type(&attestation) == 0, 0); // ON_CHAIN = 0
            assert!(attestation::is_on_chain_storage(&attestation), 0);
            assert!(!attestation::is_off_chain_storage(&attestation), 0);
            
            // Verify data is available for on-chain storage
            let retrieved_data = attestation::data(&attestation);
            assert!(retrieved_data == data, 0);
            
            // Verify off-chain fields are empty/not set
            assert!(option::is_none(&attestation::walrus_blob_id(&attestation)), 0);
            assert!(option::is_none(&attestation::data_hash(&attestation)), 0);
            assert!(!attestation::is_encrypted(&attestation), 0);
            assert!(option::is_none(&attestation::seal_policy_id(&attestation)), 0);
            
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_verify_data_integrity() {
        let admin: address = @0x1;
        let user: address = @0x2;

        let schema: vector<u8> = b"name: string";
        let name: vector<u8> = b"Test";
        let description: vector<u8> = b"Test";
        let url: vector<u8> = b"https://example.com";

        let correct_data: vector<u8> = b"alice";
        let incorrect_data: vector<u8> = b"bob";
        let walrus_sui_object_id: address = @0x1111111111111111111111111111111111111111;
        let walrus_blob_id: vector<u8> = b"test-blob-id-base64url";
        let data_hash = hash::blake2b256(&correct_data);
        let encrypted = false;
        let seal_nonce: Option<vector<u8>> = option::none();
        let seal_policy_id: Option<address> = option::none();

        // init
        let mut scenario = test_scenario::begin(admin);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        // make schema
        test_scenario::next_tx(&mut scenario, admin);
        {   
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let admin_cap = sas::register_schema(
                &mut schema_registry, 
                schema, 
                name, 
                description,
                url,
                true, 
                test_scenario::ctx(&mut scenario)
            );
            
            transfer::public_transfer(admin_cap, admin);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };
        
        // make attestation with off-chain storage
        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            sas::attest_off_chain(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                user,
                0,
                walrus_sui_object_id,
                walrus_blob_id,
                data_hash,
                encrypted,
                seal_nonce,
                seal_policy_id,
                name,
                description,
                url,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            clock::share_for_testing(clock);
        };
        
        // Test data integrity verification
        test_scenario::next_tx(&mut scenario, user);
        {
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            
            // Verify correct data passes integrity check
            assert!(attestation::verify_data_integrity(&attestation, correct_data), 0);
            
            // Verify incorrect data fails integrity check
            assert!(!attestation::verify_data_integrity(&attestation, incorrect_data), 0);
            
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = ::sas::sas_tests::ENotImplemented)]
    fun test_sas_fail() {
        abort ENotImplemented
    }
}
