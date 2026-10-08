#!/usr/bin/env bash
sqlcmd_exec(){
  local q=$1
  docker exec -e SQLCMDPASSWORD="$(secret_value MSSQL_SA_PASSWORD)" mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -Q "$q"
}
database_wait(){
  local i; for i in $(seq 1 60); do docker exec mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$(secret_value MSSQL_SA_PASSWORD)" -C -Q 'SELECT 1' >/dev/null 2>&1 && return 0; sleep 5; done; return 1
}
database_initialize(){
  need_root; docker inspect mssql >/dev/null 2>&1 || install_database; database_wait || die "SQL Server did not become ready"
  local ssc_user ssc_pwd dast_user dast_pwd
  ssc_user=$(secret_value SSC_DB_USER); ssc_pwd=$(secret_value SSC_DB_PASSWORD); dast_user=$(secret_value DAST_DB_USER); dast_pwd=$(secret_value DAST_DB_PASSWORD)
  [[ "$ssc_user" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "$dast_user" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Database usernames must be simple SQL identifiers"
  local esc_ssc=${ssc_pwd//\'/\'\'} esc_dast=${dast_pwd//\'/\'\'}
  warn "This creates or repairs database principals. Existing application tables are not dropped."
  confirm "Create/repair SSC and DAST databases and logins?" || return 0
  sqlcmd_exec "IF DB_ID(N'SSC') IS NULL CREATE DATABASE SSC COLLATE SQL_Latin1_General_CP1_CS_AS;"
  sqlcmd_exec "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'$ssc_user') CREATE LOGIN [$ssc_user] WITH PASSWORD=N'$esc_ssc'; ELSE ALTER LOGIN [$ssc_user] WITH PASSWORD=N'$esc_ssc';"
  sqlcmd_exec "USE SSC; IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'$ssc_user') CREATE USER [$ssc_user] FOR LOGIN [$ssc_user]; ALTER ROLE db_owner ADD MEMBER [$ssc_user];"
  sqlcmd_exec "IF DB_ID(N'DAST') IS NULL CREATE DATABASE DAST COLLATE SQL_Latin1_General_CP1_CS_AS;"
  sqlcmd_exec "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'$dast_user') CREATE LOGIN [$dast_user] WITH PASSWORD=N'$esc_dast'; ELSE ALTER LOGIN [$dast_user] WITH PASSWORD=N'$esc_dast';"
  sqlcmd_exec "USE DAST; IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'$dast_user') CREATE USER [$dast_user] FOR LOGIN [$dast_user]; ALTER ROLE db_owner ADD MEMBER [$dast_user];"
  database_validate
}
database_validate(){ database_wait || die "MSSQL unavailable"; sqlcmd_exec "SELECT name,collation_name,state_desc FROM sys.databases WHERE name IN ('SSC','DAST');"; ok "SQL Server databases reachable"; }
database_backup(){
  need_root; database_wait || die "MSSQL unavailable"; local stamp dir hostdir; stamp=$(date +%Y%m%d-%H%M%S); dir=/var/opt/mssql/backup; hostdir="$FORTIFY_HOME/backups/$stamp/database"; mkdir -p "$hostdir"; docker exec mssql mkdir -p "$dir"
  sqlcmd_exec "BACKUP DATABASE SSC TO DISK=N'$dir/SSC-$stamp.bak' WITH INIT,CHECKSUM; BACKUP DATABASE DAST TO DISK=N'$dir/DAST-$stamp.bak' WITH INIT,CHECKSUM;"
  docker cp "mssql:$dir/SSC-$stamp.bak" "$hostdir/"; docker cp "mssql:$dir/DAST-$stamp.bak" "$hostdir/"; chmod 600 "$hostdir"/*; ok "Database backups copied to $hostdir"
}
