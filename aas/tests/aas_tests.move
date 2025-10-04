#[test_only]
module aas::aas_tests {
    use aptos_framework::string;
    use aptos_framework::signer;
    use aptos_framework::timestamp;
    use aptos_std::aptos_hash::{blake2b_256};

    use aas::schema;
    use aas::attestation;
    use aas::aas;
    use aas::test_helpers;

    #[test(publisher = @0x101, test_account = @0xcafe)]
    fun test_e2e(publisher: &signer, test_account: &signer) {
        test_helpers::setup(publisher);

        let schema_raw: vector<u8> = b"name: String, age: u16";
        let name = string::utf8(b"Profile");
        let description = string::utf8(b"User Profile");
        let uri = string::utf8(b"www.google.com");
        
        // create a new schema
        let schema_addr = aas::create_schema_and_get_schema_address(
            test_account,
            schema_raw,
            name,
            description,
            uri,
            true,
            @0x0,
        );

        let expected_schema_address = schema::get_schema_address(
            name, 
            description,
            uri,
            true,
            @0x0,
            schema_raw,
        );

        assert!(schema_addr == expected_schema_address, 0);

        // create an attestation
        let attestation_addr = aas::create_attestation_and_get_address(
            test_account,
            signer::address_of(test_account),
            schema_addr,
            @0x0,
            0,
            true,
            b"name: alice, age: 20",
        );

        assert!(attestation::attestation_exists(attestation_addr), 1);

        // revoke the attestation
        timestamp::update_global_time_for_test_secs(10000000);
        aas::revoke_attestation(test_account, schema_addr, attestation_addr);

        let (_, _, _, _, revocation_time, _, _, _, _, _, _, _, _, _, _) = attestation::attestation_unpacked(attestation_addr);
        assert!(revocation_time == 10000000, 2);
    }

    #[test(publisher = @0x101, test_account = @0xface)]
    fun test_off_chain_attestation(publisher: &signer, test_account: &signer) {
        test_helpers::setup(publisher);

        let schema_raw: vector<u8> = b"name: String, age: u16";
        let name = string::utf8(b"Profile");
        let description = string::utf8(b"User Profile");
        let uri = string::utf8(b"www.google.com");

        let schema_addr = aas::create_schema_and_get_schema_address(
            test_account,
            schema_raw,
            name,
            description,
            uri,
            true,
            @0x0,
        );

        let off_chain_data: vector<u8> = b"alice, 100";
        let off_chain_data_for_hash: vector<u8> = b"alice, 100";
        let data_hash = blake2b_256(off_chain_data_for_hash);
        let shelby_account = signer::address_of(test_account);
        let shelby_blob_name = string::utf8(b"attestations/profile/alice");

        let attestation_addr = aas::create_attestation_off_chain_and_get_address(
            test_account,
            signer::address_of(test_account),
            schema_addr,
            @0x0,
            0,
            true,
            data_hash,
            shelby_account,
            shelby_blob_name,
            b"merkle-root",
            b"register-tx-hash",
        );

        assert!(attestation::attestation_exists(attestation_addr), 10);
        assert!(attestation::storage_type(attestation_addr) == 1, 11);
        assert!(attestation::verify_data_integrity(attestation_addr, off_chain_data), 12);
        assert!(attestation::shelby_account(attestation_addr) == shelby_account, 13);
        assert!(string::length(&attestation::shelby_blob_name(attestation_addr)) > 0, 14);
    }

}
