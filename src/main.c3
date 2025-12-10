module pwm;
import db;
import std::io;
import pwm::vault;

fn int main(String[] args) {
    const ZString FILENAME = (ZString) "password";
    int rc = vault::create_vault(FILENAME);
    if ( rc != db::SQLITE_OK ) {
        return 1;
    }

    rc = vault::update_password(FILENAME, "test.com", "admin", "admin");
    if ( rc != db::SQLITE_OK) {
        return 1;
    }

    rc = vault::return_password(FILENAME, "test.com", "admin");
    if ( rc != db::SQLITE_OK) {
        return 1;
    }

    return 0;
}

