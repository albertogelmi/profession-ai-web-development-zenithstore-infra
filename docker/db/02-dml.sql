-- Set character set to UTF-8
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

INSERT INTO zenithstore.`user` (id,start_date,first_name,last_name,is_active,is_blocked,end_date) VALUES
	 ('MATR0001',CURRENT_TIMESTAMP,'Alberto','Gelmi',1,0,NULL),
	 ('MATR0002',CURRENT_TIMESTAMP,'Luca','Rossi',1,0,NULL),
	 ('MATR0003',CURRENT_TIMESTAMP,'Matteo','Bianchi',1,0,NULL);

INSERT INTO zenithstore.user_credential (user_id,start_date,password_hash,is_active,end_date) VALUES
	 ('MATR0001',CURRENT_TIMESTAMP,'$2b$12$pl6oeEPu4YddRl2EFVjf0.Vk1P.WRwbhB45rwfCpjuwnRikAB8d5y',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH)),
	 ('MATR0002',CURRENT_TIMESTAMP,'$2b$12$rkwQCNS74wxrQWBJNqeAJuw1w1ey0rBWxUXeA0StZRg9VEEHQXQsy',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH)),
	 ('MATR0003',CURRENT_TIMESTAMP,'$2b$12$JHDlFWo9TO/tiDmbepgknO319zVSGiMWJS1TwszbY.FwUVBdftvUq',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH));

INSERT INTO zenithstore.customer (start_date,first_name,last_name,email,is_active,is_blocked,end_date) VALUES
	 (CURRENT_TIMESTAMP,'Marta','Verdi','marta.verdi@gmail.com',1,0,NULL),
	 (CURRENT_TIMESTAMP,'Marco','Bianchi','marco.bianchi@gmail.com',1,0,NULL),
	 (CURRENT_TIMESTAMP,'Matteo','Rossi','matteo.rossi@gmail.com',1,0,NULL);

INSERT INTO zenithstore.customer_credential (customer_id,start_date,password_hash,is_active,end_date) VALUES
	 (1,CURRENT_TIMESTAMP,'$2b$12$K9cvW168EIIhnkqdsxB37ua2C8/FK.N/2Llll.Zfkcxr6eEHaJdYq',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH)),
	 (2,CURRENT_TIMESTAMP,'$2b$12$CvQydP2GeqM1RHn.E80OtOe61lo2CLlmvNEjwh4GQLCkix6hLYTOm',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH)),
	 (3,CURRENT_TIMESTAMP,'$2b$12$MjBEApHN8VkM.eSu/c3HTOVlSSozW2Gg3sUblV4cjrTvzWAgWQ2Tm',1,ADDDATE(CURRENT_TIMESTAMP, INTERVAL 3 MONTH));

INSERT INTO zenithstore.product_master (product_code,created_at,created_by) VALUES
	 ('PRODOTTO01',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO02',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO03',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO04',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO05',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO06',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO07',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO08',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO09',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO10',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO11',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO12',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO13',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO14',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO15',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO16',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO17',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO18',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO19',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO20',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO21',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO22',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO23',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO24',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO25',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO26',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO27',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO28',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO29',CURRENT_TIMESTAMP,'MATR0001'),
	 ('PRODOTTO30',CURRENT_TIMESTAMP,'MATR0001');

INSERT INTO zenithstore.category (slug,name,description,icon,display_order,is_active,created_by) VALUES
	 ('elettronica','Elettronica','Dispositivi elettronici, computer, smartphone e accessori tecnologici','laptop',1,1,'MATR0001'),
	 ('abbigliamento','Abbigliamento','Abbigliamento uomo, donna e bambino per tutte le stagioni','tshirt',2,1,'MATR0001'),
	 ('casa-e-cucina','Casa e Cucina','Articoli per la casa, decorazioni, utensili da cucina e complementi d''arredo','home',3,1,'MATR0001'),
	 ('sport','Sport','Attrezzature sportive, abbigliamento fitness e accessori per lo sport','dumbbell',4,1,'MATR0001'),
	 ('libri','Libri','Libri di tutti i generi, ebook e audiolibri','book',5,1,'MATR0001'),
	 ('giocattoli','Giocattoli','Giocattoli per bambini di tutte le età, giochi educativi e peluche','puzzle-piece',6,1,'MATR0001');

INSERT INTO zenithstore.product_version (product_master_id,name,description,price,category_slug,created_by,start_date,updated_by,last_update,is_active,deleted_by,end_date) VALUES
	 (1,'Luce Serena LED','Lampada da tavolo con diffusore in vetro satinato e base in metallo nero opaco, ideale per un''illuminazione d''atmosfera in soggiorno o camera da letto.',49.50,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (2,'Tela Natura Cornice XXL','Cornice da parete extra large (80x120 cm) in legno riciclato, finitura bianco decapato, perfetta per valorizzare stampe o fotografie speciali.',129.00,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (3,'Vaso Elegance Ceramica','Vaso alto 45 cm in ceramica smaltata color grafite, design minimalista, adatto sia come oggetto decorativo che contenitore per fiori secchi.',79.00,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (4,'Cesto Multiuso Intreccio','Cesto da 40x30 cm intrecciato a mano in fibra naturale, manici in cuoio, utile come contenitore per riviste, plaid o giochi, perfetto per l''ingresso o il living.',39.99,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (5,'Diffusore Aromi Premium','Diffusore a bastoncini con fragranza legno-ambra, bottiglia in vetro fumé da 500 ml e bastoncini inclusi; così da dare un tocco olfattivo raffinato agli ambienti.',46.20,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (6,'Set 2 Cuscini Comfort + Zip','Coppia di cuscini 50x50 cm in lino lavato (colore naturale) con interno morbido in fibra anallergica e fodera removibile tramite zip.',35.90,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (7,'Specchio Forma Libera Large','Specchio da parete senza cornice, forma organica (irregolare), dimensioni circa 90x70 cm, ideale per creare un punto luce nel corridoio o come elemento decorativo in camera',99.99,'casa-e-cucina','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (8,'Smartphone XPhone Pro','Smartphone di ultima generazione con display OLED da 6.5", fotocamera tripla da 48MP, 128GB di memoria interna e batteria a lunga durata.',799.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (9,'Laptop UltraBook 15"','Laptop leggero con processore Intel i7, 16GB di RAM, SSD da 512GB e schermo Full HD da 15.6", ideale per lavoro e intrattenimento.',1199.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (10,'Cuffie Wireless SoundMax','Cuffie over-ear con cancellazione del rumore, connessione Bluetooth 5.0, autonomia fino a 20 ore e microfono integrato per chiamate.',199.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (11,'T-Shirt Basic Uomo','Maglietta in cotone 100% con vestibilità regolare, disponibile in vari colori e taglie dalla S alla XXL.',19.90,'abbigliamento','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (12,'Jeans Slim Fit Donna','Jeans a gamba stretta in denim elasticizzato, lavaggio scuro, con chiusura a zip e bottoni, disponibili dalla taglia 26 alla 34.',49.90,'abbigliamento','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (13,'Felpa con Cappuccio Unisex','Felpa in cotone e poliestere, con cappuccio regolabile, tasca frontale a marsupio e disponibile in diverse colorazioni.',39.90,'abbigliamento','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (14,'Giacca Impermeabile Uomo','Giacca leggera e impermeabile con cappuccio ripiegabile, tasche con zip e fodera traspirante, ideale per le giornate piovose.',89.90,'abbigliamento','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (15,'Abito Estivo Donna','Abito lungo in tessuto leggero con stampa floreale, spalline sottili e cintura in vita, perfetto per le giornate estive.',59.90,'abbigliamento','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (16,'Zaino Sportivo 20L','Zaino resistente all''acqua con capacità di 20 litri, scomparti multipli e spallacci imbottiti, ideale per attività sportive e gite all''aria aperta.',49.90,'sport','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (17,'Pallone da Calcio Pro','Pallone da calcio ufficiale in materiale sintetico, taglia 5, con design aerodinamico per un miglior controllo e precisione nei tiri.',29.90,'sport','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (18,'Tapis Roulant Elettrico','Tapis roulant pieghevole con velocità regolabile fino a 12 km/h, display LCD per monitorare tempo, distanza e calorie bruciate.',499.00,'sport','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (19,'Set di Pesi Regolabili','Set di manubri regolabili da 2 a 20 kg ciascuno, con impugnature antiscivolo e supporto incluso per un facile stoccaggio.',149.00,'sport','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (20,'Romanzo Thriller "Ombre Nascoste"','Romanzo thriller avvincente che segue le indagini di un detective alle prese con un misterioso serial killer in una città oscura e pericolosa.',14.90,'libri','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (21,'Manuale di Cucina Vegetariana','Libro di ricette vegetariane facili e gustose, con consigli nutrizionali e suggerimenti per una dieta equilibrata.',24.90,'libri','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (22,'Guida al Viaggio in Europa','Guida completa per viaggiare in Europa, con itinerari consigliati, attrazioni principali e suggerimenti pratici per i turisti.',19.90,'libri','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (23,'Puzzle 1000 Pezzi "Paesaggio Montano"','Puzzle da 1000 pezzi con immagine di un suggestivo paesaggio montano, ideale per momenti di relax e divertimento in famiglia.',15.90,'giocattoli','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (24,'Gioco da Tavolo "Strategia & Avventura"','Gioco da tavolo per 2-6 giocatori, che combina elementi di strategia e avventura in un mondo fantastico pieno di sfide e sorprese.',39.90,'giocattoli','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (25,'Peluche Orso Gigante 1.5m','Peluche a forma di orso gigante alto 1.5 metri, realizzato in morbido tessuto peluche, perfetto come regalo speciale per bambini e adulti.',59.90,'giocattoli','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (26,'Set Costruzioni Magnetiche 100 Pezzi','Set di costruzioni magnetiche con 100 pezzi colorati, che permettono di creare forme e strutture tridimensionali in modo semplice e divertente.',49.90,'giocattoli','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (27,'Drone con Fotocamera 4K','Drone pieghevole con fotocamera 4K, controllo tramite app, modalità di volo automatica e stabilizzazione dell''immagine per riprese aeree di alta qualità.',299.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (28,'Smartwatch Fitness Tracker','Smartwatch con monitoraggio della frequenza cardiaca, conteggio dei passi, notifiche smartphone e resistenza all''acqua, ideale per uno stile di vita attivo.',149.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (29,'Tablet 10" HD','Tablet con schermo da 10 pollici HD, processore quad-core, 4GB di RAM e 64GB di memoria interna, perfetto per navigare, leggere e guardare video in mobilità.',249.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL),
	 (30,'Speaker Bluetooth Portatile','Speaker Bluetooth portatile con suono stereo, batteria ricaricabile fino a 10 ore di riproduzione e resistenza all''acqua, ideale per ascoltare musica ovunque.',89.00,'elettronica','MATR0001',CURRENT_TIMESTAMP,'MATR0001',CURRENT_TIMESTAMP,1,NULL,NULL);

INSERT INTO zenithstore.inventory_quantity (product_master_id,available_quantity,reserved_quantity,safety_stock,updated_by_user,updated_by_order,last_update) VALUES
	 (1,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (2,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (3,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (4,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (5,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (6,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (7,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (8,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (9,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (10,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (11,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (12,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (13,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (14,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (15,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (16,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (17,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (18,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (19,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (20,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (21,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (22,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (23,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (24,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (25,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (26,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (27,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (28,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (29,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP),
	 (30,10,0,1,'MATR0001',NULL,CURRENT_TIMESTAMP);
