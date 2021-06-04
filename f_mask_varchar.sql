create or replace function f_mask_varchar (varchar, varchar, varchar)
  returns varchar
immutable
as $$
  select case 
    when $3 is null then null 
    when $3 = 'N' then $1
    when $3 = 'F' then md5($1)
    else case $2 
      when 'ssn' then substring($1, 1, 7)||'xxxx'
      when 'email' then substring(SPLIT_PART($1, '@', 1), 1, 3) + 'xxxx@' + SPLIT_PART($1, '@', 2)
      else substring($1, 1, 3)||'xxxxx' end
    end
$$ language sql;
