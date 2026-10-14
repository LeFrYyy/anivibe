-- Approved originals created for Anivibe. No external/GIF upload is accepted.
begin;
insert into public.cosmetic_media(id,asset_key,poster_key,mime,byte_length,width,height,duration,sha256,approved) values('orbit','orbit','orbit','video/mp4',9181,192,192,3,'bdda5104aa196ff159235881fe9352dc9f55a351bdc0068b2878174f9a78244e',true);
insert into public.shop_items(id,name,category,price,media_id) values('orbit','Орбита','avatar',100,'orbit');
insert into public.cosmetic_media(id,asset_key,poster_key,mime,byte_length,width,height,duration,sha256,approved) values('duet','duet','duet','video/mp4',12482,192,192,3,'3514e8021e4881d8d605a7fb499c40dcbd002e958e74f62cb69a8034ffc637aa',true);
insert into public.shop_items(id,name,category,price,media_id) values('duet','Созвездие','avatar',250,'duet');
insert into public.cosmetic_media(id,asset_key,poster_key,mime,byte_length,width,height,duration,sha256,approved) values('horizon','horizon','horizon','image/png',20797,640,240,null,'1c9e9de3dc3d0b813e3316b9fb874578605010dafe5a373cb28429aedb1ae805',true);
insert into public.shop_items(id,name,category,price,media_id) values('horizon','Тихий горизонт','banner',150,'horizon');
insert into public.cosmetic_media(id,asset_key,poster_key,mime,byte_length,width,height,duration,sha256,approved) values('afterglow','afterglow','afterglow','video/mp4',38665,640,240,3,'9e61d7b82f6ac806b7aa8000d5e1e26621069ada687c5507d87ee19b675832c1',true);
insert into public.shop_items(id,name,category,price,media_id) values('afterglow','Послесвечение','animated_banner',400,'afterglow');
notify pgrst,'reload schema';
commit;
