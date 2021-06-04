create or replace function f_mask_bigint (bigint, varchar, varchar)
  returns bigint
immutable
as $$
  select case 
    when $3 is null then null 
    when $3 = 'N' then $1
    when $3 = 'F' then strtol(substr(md5($1), 1,15), 16)
    else case $2 
      when 'cc' then mod($1, 1000)
      else substring($1::varchar, 1, 3)::int end
    end
$$ language sql;
