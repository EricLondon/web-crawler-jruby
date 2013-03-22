create sequence links_serial;
create sequence docs_serial;
create sequence annotations_serial;
create sequence images_serial;
create sequence emails_serial;


create table links (id bigint primary key default nextval('links_serial'), created_at timestamp default current_timestamp, visited_at timestamp, content text not null, href text not null, parent_id bigint, prospect_score smallint,  fountain_score smallint, CHECK (href <> ''));

create table docs (id bigint primary key default nextval('docs_serial'), created_at timestamp default current_timestamp, content text not null, link_id bigint, job boolean, is_job_label boolean CHECK (content <> ''));

create table annotations (id int primary key default nextval('annotations_serial'), created_at timestamp default current_timestamp, selection text not null, label text not null, doc_id bigint, CHECK (selection <> '' and label <> ''));

create table images (id bigint primary key default nextval('images_serial'), link_id bigint, alt text, url text, filename text);

alter table images add column height integer;
alter table images add column width integer;

create index on links(visited_at, prospect_score);
create unique index on links (href);

alter table docs add column hashtext text;
create unique index on docs (link_id, hashtext);

alter table images drop column height;
alter table images drop column width;
alter table images drop column filename;
create unique index on images(link_id, url);

create index on links (parent_id);
alter table links add column domain text;


drop index links_visited_at_prospect_score_idx;

create type links_info as (id bigint, domain text, score smallint);
create index on links (prospect_score desc nulls last, id desc, visited_at);

alter table docs add constraint sane_length check (length(content) < 60000);
alter table links alter column domain set not null;
alter table links add constraint links_sane_length check (length(href) < 1001);

create table emails (id bigint primary key default nextval('emails_serial'), created_at timestamp default current_timestamp, link_id bigint, address text not null CHECK (address <> ''));

