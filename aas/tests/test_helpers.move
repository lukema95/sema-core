#[test_only]
module aas::test_helpers {
    use aas::package_manager;
    use aas::resolver_storage;

    public fun setup(publisher: &signer) {
        package_manager::initialize_for_test(publisher);
        resolver_storage::initialize();
    }
}