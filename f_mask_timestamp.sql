create or replace function f_mask_timestamp (timestamp, varchar, varchar)
  returns timestamp
volatile
as $$
  select case 
    when $3 is null then null 
    when $3 = 'N' then $1
    when $3 = 'F' then dateadd(day, (random() * 100)::int-50, '1/1/2021'::date)
    else case $2 
      when 'dob' then date_trunc('year',$1)
      else dateadd(year, -1*date_part('year', $1)::int+1900,$1) end
    end
$$ language sql;
