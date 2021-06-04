# Amazon Redshift - Dynamic Data Masking

## Overview
Increasingly organizations are using their data warehouse to store customer sensitive data (PII and PCI).  The challenge arises on how to store that data securely but expose that data in a way that is performant, cost optimized, and easy to manage in terms of masking rules and access controls.  Dynamic data masking is a strategy that enables customers to specify how much sensitive data to reveal with minimal impact on the application layer. Using the following strategy, you can implement a dynamic data masking strategy within Amazon Redshift.

## Installation
To install these procedures download thie repository and execute the `create_udfs.py` script.  The tool will prompt for the cluster connection details.

> Ensure `python3` and the `redshift_connector` library is installed. `pip3 install redshift_connector`

```console
foo@bar:~$ python3 create_udfs.py
Cluster Host:
Database Name:
User:
Port:
Password:
```

## Requirements
Let's list out the requirements in more detail to ensure the solution meets the requirements:

1. [Masking rules](#masking-rules) may be different by column based on type (i.e. Email, SSN, Generic, Date of Birth).  Each column can be `tagged` with a type to drive the rule which should be used.
2. [Masking privileges](#masking-privileges) can be assigned at the user level and are are applicable to any DB object the user has access to. However, access to the DB object is still controlled at the DB user/group level.  If a field is tagged as PII, privileges include:
    1. FullMask – the data is returned obfuscated, but it is not possible to determine the original value.
    2. PartialMask – part of the input value is masked while part is not masked.
    3. NoMasking – the input value is returned.
    4. Undefined – the user has not been assigned an above privilege and NULL will be returned.
3. [Query performance](#query-performance) should be as close to original performance as possible.
4. [Application impact](#application-impact) should be minimal.
5. [Compliance, audits and controls](#compliance) are in place and auditors can determine who:
    1. modified masking rules
    2. modified masking privileges
    3. masked data

## Masking Rules
The masking rules can be assigned per table by ensuring users do not have access to the raw data and instead have access to a [view](#view-definition).  Within the view each PII field will be wrapped in a [function](#function-defintion) which is dymamically passed the [masking privilege](#masking-privileges) based on the user which is logged in.  In the function you can also pass the tag which describes the tag-specific masking rules.

### View Definition
In the following example, I've created a sample dataset with customer data.

```sql
drop table if exists public.customer_raw;
create table public.customer_raw(id int, first_name varchar(100), last_name varchar(100), login varchar(100), email_address varchar(100));
insert into public.customer_raw values
 (1,'Jane','Doe','jdoe','jdoe@org.com'),
 (2,'John','Doe','jhndoe','jhndoe@org.com'),
 (3,'Edward','Jones','ejones','ejones@org.com'),
 (4,'Mary','Contrary','mcontrary','mcontrary@org.com');
```

Now I can create a view which wraps the PII fields in my masking function.  This view also joins to the `user_entitle` table to determine the user's masking privilege.  This view is dynamic becuase it leverages the `current_user` variable which will be different for each user logged into the system.

```sql
create or replace view public.customer as (
  select c.id,
    f_mask_varchar(c.first_name, 'name', e.priv) first_name,
    f_mask_varchar(c.last_name, 'name', e.priv) last_name,
    f_mask_varchar(c.login, 'login', e.priv) login,
    f_mask_varchar(c.email_address,'email', e.priv) email
  from  public.customer_raw c
  left join public.user_entitle e on (current_user = e.username)
) with no schema binding;
```

Finally, I can grant access to the `customer` view.  While in this example the grants to the `customer` view have been done for the individual user, it can also be granted at user group level. Notice: I have not granted access to the raw dataset to these users, only the view.  

```sql
grant select on customer to u_fullmask;
grant select on customer to u_partialmask;
grant select on customer to u_nomask;
grant select on customer to u_newuser;
```

### Function Definition
For this view to work, we need to create the masking function `f_mask_varchar`.  For masking rules against other datatypes (e.g. INT, DATE) use the function `f_mask_int` and `f_mask_date`.  Notice: The function contains partial masking rules for `ssn` and `email` but we have also tagged our data with `name` and `login`.  For those `tags` the function can use the default masking strategy.

```sql
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
```

## Masking Privileges
Masking privileges can be managed through a user entitlement table.  Similar to the following:

```sql
drop table if exists public.user_entitle;
create table public.user_entitle (username varchar(25), priv varchar(1));
```

Create some sample users and load them into the entitlement table.  Notice: `u_newuser` has not been inserted to simulate what happens when a user has not been entitled.  While in this example the grants to the `user_entitle` table have been done for the individual user, it can also be granted at user group level.

```sql
create user u_fullmask password disable;
create user u_partialmask password disable;
create user u_nomask password disable;
create user u_newuser password disable;

grant select on user_entitle to u_fullmask;
grant select on user_entitle to u_partialmask;
grant select on user_entitle to u_nomask;
grant select on user_entitle to u_newuser;

insert into public.user_entitle values
 ('u_fullmask', 'F'),
 ('u_partialmask', 'P'),
 ('u_nomask', 'N');
```

## Query Performance
Now I can execute my `select` simulating the experience for different users.  The performance for each user is fast and the results are dynamically returned.

```sql
SET SESSION AUTHORIZATION 'u_fullmask';
select * from customer;
```
|id|first_name|last_name|login|email|
|--|--|--|--|--|
|1|2b95993380f8be6bd4bd46bf44f98db9|ad695f53ae7569fb981fc95598e27e67|a31405d272b94e5d12e9a52a665d3bfe|c51f82d521e9a9a847cc035e6e92d8b4|
|2|61409aa1fd47d4a5332de23cbf59a36f|ad695f53ae7569fb981fc95598e27e67|8857d114f83c7d42aee4888cbdc019b0|708a5de130f051ccdb124c8719afeaec|
|3|243f63354f4c1cc25d50f6269b844369|59830e37ce261d31ad0da0d5d270d0e1|8fde7a3089daf8e44d40ebe91dc33eb3|33321a32f18a25bf3a0f7d04ce60664c|
|4|e39e74fb4e80ba656f773669ed50315a|6676b8a45c4b6629faa651549418f27d|25169963ce992624a6ccaa82639e2903|d9cd3ead4c0e8bd8d56981399dbc17fb|

```sql
SET SESSION AUTHORIZATION 'u_partialmask';
select * from customer;
```
|id|first_name|last_name|login|email|
|--|--|--|--|--|
|1|Janxxxxx|Doexxxxx|jdoxxxxx|jdoxxxx@org.com|
|2|Johxxxxx|Doexxxxx|jhnxxxxx|jhnxxxx@org.com|
|3|Edwxxxxx|Jonxxxxx|ejoxxxxx|ejoxxxx@org.com|
|4|Marxxxxx|Conxxxxx|mcoxxxxx|mcoxxxx@org.com|

```sql
SET SESSION AUTHORIZATION 'u_nomask';
select * from customer;
```
|id|first_name|last_name|login|email|
|--|--|--|--|--|
|1|Jane|Doe|jdoe|jdoe@org.com|
|2|John|Doe|jhndoe|jhndoe@org.com|
|3|Edward|Jones|ejones|ejones@org.com|
|4|Mary|Contrary|mcontrary|mcontrary@org.com|

```sql
SET SESSION AUTHORIZATION 'u_newuser';
select * from customer;
```
|id|first_name|last_name|login|email|
|--|--|--|--|--|
|1|||||
|2|||||
|3|||||
|4|||||

## Application Impact
In the above example, the users which are querying the data will query the `customer` table and the ETL code which loads the data will access the `customer_raw` table.  One of the two application would need to be modified.  However, this strategy can also be applied with minimal modification to the application if the view object is deployed:
* In a different `schema` - the application code can set the Redshift [search path](https://docs.aws.amazon.com/redshift/latest/dg/r_search_path.html) prior to executing any code.
* In a different `db` - the application connection can be modified and the [database parameter](https://docs.aws.amazon.com/redshift/latest/mgmt/configure-jdbc-connection.html#obtain-jdbc-url) can be switched.

## Compliance
For compliance I can interrogate the [svl_statementtext](https://docs.aws.amazon.com/redshift/latest/dg/r_SVL_STATEMENTTEXT.html) and [stl_query](https://docs.aws.amazon.com/redshift/latest/dg/r_STL_QUERY.html) views for any changes.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
