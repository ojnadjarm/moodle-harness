#!/usr/bin/env bash
# mdb against fixture pgsql / mysqli trees with a fake docker on PATH (never real docker).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mdb"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cfg() { mkdir -p "$T/$1/www/vendor/bin" "$T/$1/www/public/local/x"; touch "$T/$1/www/vendor/bin/phpunit"
    printf "<?php\n\$CFG->dbtype    = '%s';\n\$CFG->dbhost    = 'db';\n\$CFG->dbname    = 'moodle';\n\$CFG->dbuser    = 'moodle';\n\$CFG->dbpass    = 'p@ss';\n\$CFG->prefix    = '%s';\n\$CFG->phpunit_prefix = 'phpu_';\n" "$2" "$3" > "$T/$1/www/config.php"; }
cfg pg pgsql mdl_; cfg my mysqli m_; cfg nodb pgsql mdl_; cfg none pgsql mdl_
mkdir -p "$T/bin"

# Fake docker: app containers pg/my/nodb (projects of the same name); db containers only for pg and my.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) if [ "\$2" = --filter ]; then
            p="\${3#label=com.docker.compose.project=}"; s="\${5#label=com.docker.compose.service=}"
            case "\$p" in pg|my|pub) [ "\$s" = db ] && echo "\$p-db-1" ;; esac
        else printf 'pg-app-1\nmy-app-1\nnodb-app-1\npub-app-1\n'; fi ;;
    inspect) c="\${@: -1}"; case "\$3" in
        *Mounts*) printf '%s\t/var/www/html\n' "$T/\${c%%-*}/www" ;;
        *Labels*) echo "\${c%%-*}" ;;
    esac ;;
    exec) [ "\$2" = -i ] || exit 0
        printf '%s\n' "\$*" > "$T/argv.log"; cat > "$T/stdin.log"
        if [ -n "\${FAKE_OUT+x}" ]; then printf '%s' "\$FAKE_OUT"; else printf 'id\tusername\n2\tadmin\n3\tNULL\n'; fi
        exit "\${FAKE_RC:-0}" ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$T/$1/www/public/local/x" && shift && PATH="$T/bin:$PATH" "$S" "$@" 2>&1; echo "rc=$?"); }
TSV=$'id\tusername\n2\tadmin\n3\tNULL'

check "$(run pg 'select id, username from {user} where id=? or username=?' 2 "o'k")" "$TSV"$'\nrc=0' "pgsql: TSV with header, rc 0"
check "$(cat "$T/argv.log")" $'exec -i -e PGPASSWORD=p@ss -e PGOPTIONS=-c default_transaction_read_only=on pg-db-1 psql -X -q -v ON_ERROR_STOP=1 --single-transaction -A -F \t -P footer=off -P null=NULL -U moodle -d moodle' "pgsql argv: db service of the app's project, one read-only transaction"
check "$(cat "$T/stdin.log")" "select id, username from mdl_user where id=2 or username='o''k'" "pgsql: prefix, params bound and quoted"
check "$(run my 'SELECT * FROM {config} c JOIN {user} u ON 1=1')" "$TSV"$'\nrc=0' "mysqli: TSV, rc 0"
check "$(cat "$T/argv.log")" "exec -i -e MYSQL_PWD=p@ss my-db-1 mysql --batch -u moodle moodle" "mysqli argv"
check "$(cat "$T/stdin.log")" "SET SESSION TRANSACTION READ ONLY; SELECT * FROM m_config c JOIN m_user u ON 1=1" "mysqli: read-only session, prefix m_"
rm -f "$T/argv.log"
check "$(run pg 'select 1; DELETE FROM {user}')" $'mdb: \'delete\' writes; pass --write\nrc=64' "write guard: rc 64 without --write"
check "$(run pg '  -- note
  update {user} set x=1')" $'mdb: \'update\' writes; pass --write\nrc=64' "write guard: leading comment and spaces"
check "$(test -e "$T/argv.log" && echo ran || echo none)" "none" "write guard: docker exec never called"
check "$(run pg --write 'update {user} set x=?' 1)" "$TSV"$'\nrc=0' "--write: runs"
check "$(cat "$T/argv.log")" $'exec -i -e PGPASSWORD=p@ss pg-db-1 psql -X -q -v ON_ERROR_STOP=1 -A -F \t -P footer=off -P null=NULL -U moodle -d moodle' "--write: no read-only option"
check "$(run my --write 'insert into {log} values (?)' x)" "$TSV"$'\nrc=0' "mysqli --write runs"
check "$(cat "$T/stdin.log")" "insert into m_log values ('x')" "mysqli --write: no read-only SET"
check "$(FAKE_OUT=$'id,username\n2,admin\n3,\x1d\n' run pg --json 'select id, username from {user}')" '[{"id": "2", "username": "admin"}, {"id": "3", "username": null}]'$'\nrc=0' "--json: row objects, NULL -> null"
check "$(FAKE_RC=3 run pg 'select bad')" "$TSV"$'\nrc=3' "client rc passed through"
check "$(FAKE_RC=3 run pg --json 'select bad' | tail -1)" "rc=3" "--json: client rc passed through"
check "$(run pg 'select ?' 1 2)" $'mdb: more params than ? placeholders\nrc=64' "params: too many -> rc 64"
check "$(run pg 'select ?, ?' 1)" $'mdb: fewer params than ? placeholders\nrc=64' "params: too few -> rc 64"
check "$(run none 'select 1')" "mdb: no running Moodle container mounts $T/none/www/public/local/x (its env is stopped?)"$'\nrc=64' "no app container: rc 64"
check "$(run nodb 'select 1')" $'mdb: no running DB service \'db\' in compose project \'nodb\' of nodb-app-1\nrc=64' "no db container: rc 64"
check "$(cd "$T" && PATH="$T/bin:$PATH" "$S" 'select 1' 2>&1; echo "rc=$?")" "mdb: no config.php with \$CFG->dbtype above $T (not inside a Moodle code tree; or pass --env <name>)"$'\nrc=64' "outside a code tree: rc 64"
check "$(run pg 2>&1 | tail -1)" "rc=64" "no args: rc 64 usage"
# Literals, comments and quoting: ; ? {x} inside them are left alone.
check "$(run pg "select 'a;b' as x")" "$TSV"$'\nrc=0' "guard: ; inside a literal is not a split"
check "$(run pg "select '%?%', '{user}', \"?\", \$t\$;delete \$t\$, E'\\';delete', ? -- ? {user}
/* ; ? */ from {user}" 7)" "$TSV"$'\nrc=0' "guard: literals, dollar quotes, E'' and comments"
check "$(cat "$T/stdin.log")" "select '%?%', '{user}', \"?\", \$t\$;delete \$t\$, E'\\';delete', 7 -- ? {user}
/* ; ? */ from mdl_user" "params and prefix only outside literals/comments"
check "$(run pg "select 'x''; delete from t' ; delete from {user}")" $'mdb: \'delete\' writes; pass --write\nrc=64' "guard: '' escape then a real write"
check "$(run pg "select 1; \\! touch /x")" $'mdb: client meta-command (backslash outside a literal); pass --write\nrc=64' "guard: psql meta-command refused"
check "$(run my "select 1--1; delete from {user}")" $'mdb: \'delete\' writes; pass --write\nrc=64' "mysql: -- without space is not a comment"
check "$(run my "select 'a\\';delete'")" "$TSV"$'\nrc=0' "mysql: backslash escape in a literal"
check "$(run my 'select ?' 'a\' >/dev/null; cat "$T/stdin.log")" "SET SESSION TRANSACTION READ ONLY; select 'a\\\\'" "mysql: backslash in a param escaped"
check "$(run pg --json 'select 1; select 2')" $'mdb: --json takes one statement\nrc=64' "--json: one statement only"

# --json: pgsql via CSV (multi-line, tabs, 'NULL' vs null), mysql via XML.
check "$(FAKE_OUT=$'x,t,s,n,e\n"a\nb","p\tq",NULL,\x1d,\n' run pg --json 'select 1')" '[{"x": "a\nb", "t": "p\tq", "s": "NULL", "n": null, "e": ""}]'$'\nrc=0' "--json pgsql: CSV parsed"
check "$(cat "$T/argv.log")" $'exec -i -e PGPASSWORD=p@ss -e PGOPTIONS=-c default_transaction_read_only=on pg-db-1 psql -X -q -v ON_ERROR_STOP=1 --single-transaction -P format=csv -P null=\x1d -U moodle -d moodle' "--json pgsql argv"
X='<?xml version="1.0"?>
<resultset statement="select 1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <row>
	<field name="x">a
b&amp;</field>
	<field name="n" xsi:nil="true" />
	<field name="s">NULL</field>
  </row>
</resultset>'
check "$(FAKE_OUT="$X" run my --json 'select 1')" '[{"x": "a\nb&", "n": null, "s": "NULL"}]'$'\nrc=0' "--json mysql: XML parsed"
check "$(cat "$T/argv.log")" "exec -i -e MYSQL_PWD=p@ss my-db-1 mysql --batch -u moodle moodle --xml" "--json mysql argv"
check "$(FAKE_OUT='' run my --json 'update {x} set y=1' --write 2>&1 | tail -1)" "rc=64" "--json: flags must precede the sql"
check "$(FAKE_OUT='' run my --write --json 'update {x} set y=1')" '[]'$'\nrc=0' "--json: no result set -> []"
check "$(FAKE_OUT='<bad' run my --json 'select 1' 2>/dev/null | tail -1)" "rc=1" "--json: parser failure -> its rc"

# --env <name>: config from $MFIXTURE_ENVS/<name>/www[/public], any cwd; vass*, 4.5* and unknown refused.
cfg pub pgsql pub_; mv "$T/pub/www/config.php" "$T/pub/www/public/config.php"
mkdir -p "$T/vass/www" "$T/4.5/www" "$T/elsewhere"; cp "$T/pg/www/config.php" "$T/vass/www/"; cp "$T/pg/www/config.php" "$T/4.5/www/"
ln -s "$T/vass" "$T/alias"
envrun() { (cd "$T/elsewhere" && MFIXTURE_ENVS="$T" PATH="$T/bin:$PATH" "$S" "$@" 2>&1; echo "rc=$?"); }
rm -f "$T/argv.log"
check "$(envrun --env pg 'select 1 from {user}')" "$TSV"$'\nrc=0' "--env pg: runs from outside any code tree"
check "$(cut -d" " -f1-11 "$T/argv.log"; cat "$T/stdin.log")" $'exec -i -e PGPASSWORD=p@ss -e PGOPTIONS=-c default_transaction_read_only=on pg-db-1 psql -X -q\nselect 1 from mdl_user' "--env pg: that env's db container and prefix"
check "$(envrun --env pub 'select 1 from {user}' >/dev/null; cat "$T/stdin.log")" "select 1 from pub_user" "--env: config.php under www/public"
rm -f "$T/argv.log"
check "$(envrun --env vass 'select 1')" $'mdb: env \'vass\' is refused (Vass and 4.5 are never touched)\nrc=64' "--env vass: refused rc 64"
check "$(envrun --env vass-services 'select 1' | tail -1)" "rc=64" "--env vass-services: refused rc 64"
check "$(envrun --env 4.5 'select 1')" $'mdb: env \'4.5\' is refused (Vass and 4.5 are never touched)\nrc=64' "--env 4.5: refused rc 64"
check "$(envrun --env alias 'select 1')" "mdb: env 'alias' resolves to a refused env ($T/vass)"$'\nrc=64' "--env symlink to vass: refused rc 64"
mkdir -p "$T/vass/www/public" "$T/evilwww" "$T/evilcfg/www" "$T/evilpub/www"; cp "$T/pg/www/config.php" "$T/vass/www/public/"
ln -s ../vass/www "$T/evilwww/www"; ln -s "$T/vass/www/config.php" "$T/evilcfg/www/config.php"; ln -s "$T/vass/www/public" "$T/evilpub/www/public"
check "$(envrun --env evilwww 'select 1')" "mdb: env 'evilwww' resolves to a refused env ($T/vass/www)"$'\nrc=64' "--env www symlink into vass: refused rc 64"
check "$(envrun --env evilcfg 'select 1')" "mdb: env 'evilcfg' resolves to a refused env ($T/vass/www/config.php)"$'\nrc=64' "--env config.php symlink into vass: refused rc 64"
check "$(envrun --env evilpub 'select 1')" "mdb: env 'evilpub' resolves to a refused env ($T/vass/www/public)"$'\nrc=64' "--env www/public symlink into vass: refused rc 64"
check "$(envrun --env nope 'select 1')" "mdb: unknown env 'nope' (no $T/nope)"$'\nrc=64' "--env unknown: refused rc 64"
check "$(envrun --env ../pg 'select 1')" "mdb: env '../pg' is not a name under $T"$'\nrc=64' "--env path: refused rc 64"
check "$(envrun --env elsewhere 'select 1' | tail -1)" "rc=64" "--env without config.php: rc 64"
check "$(envrun --env 'select 1' | tail -1)" "rc=64" "--env without a value: usage rc 64"
check "$(test -e "$T/argv.log" && echo ran || echo none)" "none" "--env refusals: docker exec never called"
check "$(FAKE_OUT=$'id\n2\n' envrun --env pg --json 'select id from {user}')" '[{"id": "2"}]'$'\nrc=0' "--env with --json"
check "$(envrun --write --env my 'delete from {log}' >/dev/null; cat "$T/argv.log" "$T/stdin.log")" $'exec -i -e MYSQL_PWD=p@ss my-db-1 mysql --batch -u moodle moodle\ndelete from m_log' "--env with --write (mysqli)"
exit $bad
