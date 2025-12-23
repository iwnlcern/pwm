module pwm_db_tests;

import std::io;
import std::io::file;
import std::io::path;
import std::os::env;

import pwm;
import pwm::vault;
import db;

fn void ensure_dir(String path_str)
{
	if (catch err = path::mkdir(path_str, true))
	{
		(void)err;
		if (!file::exists(path_str))
		{
			unreachable("Failed to create test directory");
		}
	}
}

fn void ensure_test_dir()
{
	ensure_dir("build/test");
}

fn void ensure_test_home(String home_path)
{
	ensure_test_dir();
	ensure_dir(home_path);
	ensure_dir(home_path.tconcat("/Documents/pwm"));
}

fn void remove_if_exists(String path_str)
{
	if (file::exists(path_str))
	{
		if (catch err = file::delete(path_str))
		{
			(void)err;
			unreachable("Failed to delete test file");
		}
	}
}

fn void touch_file(String path_str)
{
	File f = file::open(path_str, "wb")!!;
	f.close()!!;
}

fn void set_home(String new_home, String *old_home, bool *had_home)
{
	String? prev = env::tget_var("HOME");
	if (catch prev)
	{
		*had_home = false;
		*old_home = "";
	}
	else
	{
		*had_home = true;
		*old_home = prev;
	}
	(void)env::set_var("HOME", new_home, true);
}

fn void restore_home(String old_home, bool had_home)
{
	if (had_home)
	{
		(void)env::set_var("HOME", old_home, true);
	}
	else
	{
		(void)env::clear_var("HOME");
	}
}

fn void test_filename_from_path() @test
{
	assert(pwm::filename_from_path("") == "");
	assert(pwm::filename_from_path("vault.db") == "vault.db");
	assert(pwm::filename_from_path("dir/sub/vault.db") == "vault.db");
	assert(pwm::filename_from_path("dir\\sub\\vault.db") == "vault.db");
	assert(pwm::filename_from_path("dir/") == "");
}

fn void test_ensure_db_extension() @test
{
	assert(pwm::ensure_db_extension("") == "");
	assert(pwm::ensure_db_extension("vault") == "vault.db");
	assert(pwm::ensure_db_extension("vault.db") == "vault.db");
	assert(pwm::ensure_db_extension("vault.backup") == "vault.backup.db");
}

fn void test_enforce_db_name_matches_filename() @test
{
	String db_name = "ignored.db";
	bool ok = pwm::enforce_db_name_matches_filename(&db_name, "build/test/custom.db", false);
	assert(ok);
	assert(db_name == "custom.db");

	String mismatch_name = "foo.db";
	ok = pwm::enforce_db_name_matches_filename(&mismatch_name, "build/test/bar.db", true);
	assert(!ok);
	assert(mismatch_name == "foo.db");

	String empty_name = "foo.db";
	ok = pwm::enforce_db_name_matches_filename(&empty_name, "build/test/", false);
	assert(!ok);
	assert(empty_name == "foo.db");
}

fn void test_registry_register_and_lookup() @test
{
	ensure_test_dir();
	String master_db = "build/test/pwm_registry_lookup.db";
	remove_if_exists(master_db);
	defer remove_if_exists(master_db);

	assert(vault::ensure_master_registry(master_db.zstr_tcopy()) == db::SQLITE_OK);

	String path_a = "build/test/pwm_lookup_a.db";
	String path_b = "build/test/pwm_lookup_b.db";

	assert(vault::register_database(master_db.zstr_tcopy(), "lookup.db", path_a.zstr_tcopy()) == db::SQLITE_OK);
	assert(vault::register_database(master_db.zstr_tcopy(), "lookup.db", path_b.zstr_tcopy()) == db::SQLITE_OK);

	vault::DbPathMatches matches = vault::lookup_database_paths(master_db.zstr_tcopy(), "lookup.db");
	assert(matches.len == 2);
	assert(matches.paths[0].str_view() == path_a);
	assert(matches.paths[1].str_view() == path_b);
}

fn void test_registry_closest_match() @test
{
	ensure_test_dir();
	String master_db = "build/test/pwm_registry_closest.db";
	remove_if_exists(master_db);
	defer remove_if_exists(master_db);

	assert(vault::ensure_master_registry(master_db.zstr_tcopy()) == db::SQLITE_OK);

	String alpha_path = "build/test/pwm_alpha.db";
	String beta_path = "build/test/pwm_beta.db";

	assert(vault::register_database(master_db.zstr_tcopy(), "alpha.db", alpha_path.zstr_tcopy()) == db::SQLITE_OK);
	assert(vault::register_database(master_db.zstr_tcopy(), "beta.db", beta_path.zstr_tcopy()) == db::SQLITE_OK);

	vault::ClosestDbMatch closest = vault::closest_database_match(master_db.zstr_tcopy(), "alpah.db");
	assert(closest.found);
	assert(closest.name == "alpha.db");
	assert(closest.path.str_view() == alpha_path);
}

fn void test_registry_prune_missing() @test
{
	ensure_test_dir();
	String master_db = "build/test/pwm_registry_prune.db";
	remove_if_exists(master_db);
	defer remove_if_exists(master_db);

	assert(vault::ensure_master_registry(master_db.zstr_tcopy()) == db::SQLITE_OK);

	String existing_path = "build/test/pwm_prune_exists.db";
	String missing_path = "build/test/pwm_prune_missing.db";
	remove_if_exists(existing_path);
	remove_if_exists(missing_path);
	touch_file(existing_path);
	defer remove_if_exists(existing_path);

	assert(vault::register_database(master_db.zstr_tcopy(), "prune.db", existing_path.zstr_tcopy()) == db::SQLITE_OK);
	assert(vault::register_database(master_db.zstr_tcopy(), "prune.db", missing_path.zstr_tcopy()) == db::SQLITE_OK);
	assert(vault::prune_missing_databases(master_db.zstr_tcopy()) == db::SQLITE_OK);

	vault::DbPathMatches matches = vault::lookup_database_paths(master_db.zstr_tcopy(), "prune.db");
	assert(matches.len == 1);
	assert(matches.paths[0].str_view() == existing_path);
}
