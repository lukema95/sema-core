#[test_only]
module resolvers::blocklist_tests {
    use sui::{
        test_scenario::{Self},
        clock::{Self}
    };
    use sas::sas::{Self};
    use sas::schema::{Schema, ResolverBuilder};
    use sas::blocklist::{Self};
    use sas::schema_registry::{Self, SchemaRegistry};
    use sas::attestation::{Self, Attestation};
    use sas::attestation_registry::{Self, AttestationRegistry};
    use sas::admin::{Admin};

    #[test]
    fun test_blocklist() {
        let alice: address = @0x1;
        let bob: address = @0x2;
        let cathrine: address = @0x3;

        let schema: vector<u8> = b"name: string, age: u64";
        let data: vector<u8> = b"alice, 100";
        let name: vector<u8> = b"Profile";
        let description: vector<u8> = b"Profile of a user";
        let url: vector<u8> = b"https://example.com";

        let mut resolver_builder: ResolverBuilder;
        let mut scenario = test_scenario::begin(alice);
        {
            schema_registry::test_init(test_scenario::ctx(&mut scenario));
            attestation_registry::test_init(test_scenario::ctx(&mut scenario));
        };

        let schema_address: address;
        let attestation_address: address;
        test_scenario::next_tx(&mut scenario, alice);
        {
            let mut schema_registry = test_scenario::take_shared<SchemaRegistry>(&scenario);
            let (builder, admin_cap, schema_record) = sas::register_schema_with_resolver(
                &mut schema_registry, 
                schema, 
                name, 
                description, 
                url, 
                true, 
                test_scenario::ctx(&mut scenario)
            );
            resolver_builder = builder;
            schema_address = schema_record.addy();
            schema_record.share_schema();

            transfer::public_transfer(admin_cap, alice);
            test_scenario::return_shared<SchemaRegistry>(schema_registry);
        };

        // Attest without resolver
        test_scenario::next_tx(&mut scenario, alice);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let mut schema_record = test_scenario::take_shared<Schema>(&scenario);
            let admin_cap = test_scenario::take_from_sender<Admin>(&scenario);

            assert!(schema_record.addy() == schema_address);

            blocklist::add(&schema_record, &mut resolver_builder, test_scenario::ctx(&mut scenario));
            schema_record.add_resolver(resolver_builder);
            
            blocklist::add_user(&admin_cap, &mut schema_record, cathrine);
            assert!(blocklist::is_blocklisted(&schema_record, cathrine));
            assert!(!blocklist::is_blocklisted(&schema_record, bob));

            let mut request = schema_record.start_attest();
            blocklist::approve(&schema_record, &mut request, test_scenario::ctx(&mut scenario));

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            attestation_address = sas::attest_with_resolver(
                &mut schema_record,
                &mut attestation_registry,
                @0x0,
                bob,
                0,
                data,
                name,
                description,
                url,
                &clock,
                request,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            transfer::public_transfer(admin_cap, alice);
            clock::share_for_testing(clock);
        };

        // Revoke with resolver
        test_scenario::next_tx(&mut scenario, alice);
        {
            let mut attestation_registry = test_scenario::take_shared<AttestationRegistry>(&scenario);
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let admin_cap = test_scenario::take_from_sender<Admin>(&scenario);

            assert!(schema_record.addy() == schema_address);
            assert!(attestation_registry.is_exist(attestation_address));
            assert!(!attestation_registry.is_revoked(attestation_address));

            let mut request = schema_record.start_revoke();
            blocklist::approve(&schema_record, &mut request, test_scenario::ctx(&mut scenario));


            sas::revoke_with_resolver(
                &admin_cap,
                &mut attestation_registry,
                &schema_record,
                attestation_address,
                request,
                test_scenario::ctx(&mut scenario)
            );

            assert!(attestation_registry.is_exist(attestation_address));
            assert!(attestation_registry.is_revoked(attestation_address));

            test_scenario::return_shared<AttestationRegistry>(attestation_registry);
            test_scenario::return_shared<Schema>(schema_record);
            transfer::public_transfer(admin_cap, alice);
        };

        test_scenario::next_tx(&mut scenario, bob);
        {
            let schema_record = test_scenario::take_shared<Schema>(&scenario);
            let attestation = test_scenario::take_from_sender<Attestation>(&scenario);
            assert!(attestation::schema(&attestation) == schema_record.addy());

            test_scenario::return_shared<Schema>(schema_record);
            test_scenario::return_to_sender<Attestation>(&scenario, attestation);
        };

        test_scenario::end(scenario);
    }
}