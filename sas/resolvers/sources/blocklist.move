/// Module: blocklist
module resolvers::blocklist {
    // === Imports ===
    use sui::table::{Self, Table};
    use std::string;
    use sas::admin::{Admin};
    use sas::schema::{Self, Schema, ResolverBuilder, Request};

    // === Errors ===
    const EInvalideSchemaAddress: u64 = 0;
    const EBlocked: u64 = 1;

    // === Constants ===
    const BLOCKLIST_RESOLVER: vector<u8> = b"blocklist";

    // === Structs ===
    public struct BlocklistResolver has drop {}

    public struct Blocklist has store {
      inner: Table<address, bool>
    }

    // === Method Aliases ===
    use fun string::utf8 as vector.utf8;
    
    // === Public-Mutative Functions ===
    public fun add(schema_record: &Schema, resolver_builder: &mut ResolverBuilder, ctx: &mut TxContext) {
        assert!(schema_record.addy() == resolver_builder.schema_address_from_builder(), EInvalideSchemaAddress);

        resolver_builder.add_resolver_module(BLOCKLIST_RESOLVER);
        resolver_builder.add_resolver_address(@resolvers);
        resolver_builder.add_rule(schema::start_attest_name().utf8(), BlocklistResolver {});
        resolver_builder.add_rule(schema::start_revoke_name().utf8(), BlocklistResolver {});
        resolver_builder.add_rule_config(BlocklistResolver {}, Blocklist { inner: table::new(ctx) });
    }

    public fun approve(schema_record: &Schema, request: &mut Request, ctx: &mut TxContext) {
        assert!(request.schema_address_from_request() == schema_record.addy(), EInvalideSchemaAddress);

        let blocklist = schema_record.config<BlocklistResolver, Blocklist>();

        assert!(!blocklist.inner.contains(ctx.sender()), EBlocked);

        request.approve(BlocklistResolver {});
    }

    // === Public-View Functions ===
    public fun is_blocklisted(schema_record: &Schema, user: address): bool {
        schema_record.config<BlocklistResolver, Blocklist>().inner.contains(user)
    }

    // === Admin Functions ===
    public fun add_user(admin: &Admin, schema_record: &mut Schema, user: address) {
        admin.assert_schema(schema_record.addy());

        let blocklist = schema_record.config_mut<BlocklistResolver, Blocklist>();

        blocklist.inner.add(user, true);
    }

    public fun remove_user(admin: &Admin, schema_record: &mut Schema, user: address) {
        admin.assert_schema(schema_record.addy());

        let blocklist = schema_record.config_mut<BlocklistResolver, Blocklist>();

        blocklist.inner.remove(user);
    }

}