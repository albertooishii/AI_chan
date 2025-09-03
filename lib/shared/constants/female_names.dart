/// Repositorio de nombres femeninos por país/idioma.
/// Incluye la lista japonesa ya usada y colecciones básicas por regiones.
class FemaleNamesRepo {
  // Helpers para definir listas largas como CSV compacto
  static List<String> _csv(String csv) =>
      csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // Listas ampliadas por idioma (CSV para evitar un nombre por línea)
  static final List<String> es = _csv(
    'María, Lucía, Sofía, Martina, Julia, Paula, Valentina, Camila, Daniela, Carla, Sara, Emma, Alba, Carmen, Elena, Noa, Aitana, Vega, Irene, Lola, '
    'Claudia, Laura, Nora, Teresa, Andrea, Nerea, Ariadna, Ainhoa, Olivia, Alicia, Marta, Iris, Aina, Alejandra, Ari, Ariadne, Ariadna, Aurelia, Aixa, '
    'Bianca, Candela, Carlota, Celia, Cristina, Diana, Elisa, Elsa, Eva, Gala, Gema, Helena, Inés, Itziar, Jimena, Laia, Lara, Leire, Leyre, Lía, '
    'Lola, Lucía, Luna, Maira, Malena, Mar, Mara, María José, Mariana, Marina, Marta, Maya, Mencía, Mía, Micaela, Mireia, Mireya, Miranda, Naiara, Naomi, '
    'Nayara, Noelia, Nuria, Paloma, Patricia, Pilar, Raquel, Rocío, Salma, Sandra, Silvia, Sofía, Tamara, Triana, Uxue, Valeria, Vera, Victoria, '
    'Xana, Yaiza, Zoe, Abril, Adriana, Agueda, Aida, Aitana, Alana, Alma, Amaya, Amelia, Amparo, Ana, Ana Belén, Anaïs, Angélica, Antonia, Araceli, '
    'Aroa, Asunción, Aurora, Beatriz, Belén, Berta, Blanca, Brenda, Caridad, Carolina, Casandra, Catalina, Cayetana, Chantal, Concepción, Consuelo, Coral, '
    'Dafne, Delia, Dolores, Dorotea, Edith, Elvira, Emilia, Esmeralda, Estefanía, Estela, Ester, Eugenia, Fátima, Fiona, Gabriela, Gloria, Graciela, Guadalupe, '
    'Inmaculada, Isabel, Isabella, Itzel, Jacqueline, Jana, Jazmín, Jennifer, Jessica, Josefa, Josefina, Juana, Judith, Julieta, Karen, Karina, Katya, Kenia, '
    'Leticia, Lidia, Lilian, Lilia, Liliana, Lorena, Lourdes, Lucero, Luciana, Luisa, Luz, Magdalena, Maite, Manuela, Marcelina, Margarita, María Fernanda, María Luisa, Mariel, Mariela, '
    'Marisol, Matilda, Mavis, Melanie, Melisa, Mercedes, Milagros, Mónica, Montserrat, Nadia, Nayeli, Noemí, Norma, Nubia, Ofelia, Olga, Paz, Penélope, Priscila, Regina, '
    'Reina, Renata, Reyes, Rita, Rosa, Rosalía, Rosario, Ruth, Samanta, Selena, Sílvia, Sonia, Susana, Tatiana, Telma, Teresa, Trinidad, Valentina, Vanessa, Verónica, '
    'Vilma, Virginia, Yamila, Yanira, Yasmina, Yolanda, Zaira, Zulema, Zully, Zenaida, Zoraida',
  );
  static final List<String> en = _csv(
    'Emma, Olivia, Ava, Sophia, Isabella, Mia, Charlotte, Amelia, Harper, Evelyn, Abigail, Emily, Elizabeth, Sofia, Avery, Ella, Scarlett, Grace, Chloe, Victoria, '
    'Madison, Luna, Camila, Aria, Layla, Penelope, Riley, Zoey, Nora, Lily, Eleanor, Hannah, Lillian, Addison, Aubrey, Ellie, Stella, Natalie, Zoe, Leah, '
    'Hazel, Violet, Aurora, Savannah, Audrey, Brooklyn, Bella, Claire, Skylar, Lucy, Paisley, Everly, Anna, Caroline, Nova, Genesis, Emilia, Kennedy, Samantha, '
    'Maya, Willow, Kinsley, Naomi, Aaliyah, Elena, Sarah, Ariana, Allison, Gabriella, Alice, Madelyn, Cora, Ruby, Eva, Serenity, Autumn, Adeline, Hailey, '
    'Gianna, Valentina, Isla, Eliana, Quinn, Nevaeh, Ivy, Sadie, Piper, Lydia, Alexa, Josephine, Emery, Julia, Delilah, Arianna, Vivian, Kaylee, Sophie, '
    'Brielle, Madeline, Peyton, Rylee, Clara, Hadley, Melanie, Mackenzie, Reagan, Adalynn, Liliana, Aubree, Jade, Katherine, Isabelle, Natalia, Raelynn, Maria, Athena, '
    'Ximena, Arya, Leilani, Taylor, Faith, Rose, Kylie, Alexandra, Mary, Margaret, Lilly, Ashley, Amaya, Eliza, Brianna, Bailey, Andrea, Khloe, Jasmine, '
    'Melody, Iris, Isla, Ryleigh, Ayla, Eden, Alyssa, Brooke, Morgan, Londyn, Jordyn, Harlow, Eloise, Diana, Sienna, Summer, Rachel, Lila, Ada, Gracie, '
    'Camille, Sloane, June, Alaina, Molly, Callie, Kendall, Blakely, Gemma, Luna, Alana, Rosemary, Catalina, Adelynn, Esther, Finley, Genevieve, Harmony, Haven, Hope',
  );
  // Nombres japoneses (copiados del provider actual)
  static final List<String> jp = _csv(
    'Ai, Aiko, Airi, Akane, Akari, Akemi, Ami, Asuka, Atsuko, Ayaka, Ayane, Ayano, Ayumi, Azusa, '
    'Chie, Chihiro, Chika, Chinatsu, Chisato, Chiyo, Eiko, Emi, Ena, Eri, Erika, Fumika, Fumino, Fuyuka, Fuyumi, '
    'Hana, Hanae, Hanako, Haruka, Harumi, Haruna, Hatsune, Hazuki, Hibiki, Hikari, Himari, Hinako, Hinata, Hisako, Hiyori, '
    'Honoka, Hotaru, Ibuki, Izumi, Jun, Junko, Kaho, Kana, Kanae, Kanako, Kanna, Kanon, Kaori, Kasumi, Katsumi, Kayo, '
    'Kazue, Kazuko, Kazumi, Kei, Keiko, Kikue, Kiyomi, Koharu, Kokoro, Kotone, Kumi, Kumiko, Kurumi, Kyoko, Madoka, Mai, '
    'Maiko, Maki, Makoto, Mami, Mana, Manami, Mariko, Marina, Masami, Masumi, Matsuri, Mayu, Mayuko, Mayumi, Megu, Megumi, '
    'Mei, Mie, Mieko, Miharu, Miho, Mika, Mikako, Miki, Miku, Mina, Minami, Minori, Mio, Misaki, Misato, Mitsue, Mitsuki, '
    'Mitsuko, Mitsuru, Miyako, Miyu, Mizue, Mizuki, Momoka, Momoko, Mutsumi, Naho, Namie, Nana, Nanami, Nao, Naoko, Narumi, '
    'Natsue, Natsuki, Natsuko, Natsumi, Noa, Nobuko, Noriko, Nozomi, Rei, Reika, Reiko, Reina, Remi, Rena, Rie, Rika, Riko, '
    'Rin, Rina, Rio, Risa, Risako, Rui, Rumi, Rumiko, Ruri, Ryoko, Sachie, Sachiko, Sae, Saki, Sakura, Sana, Sanae, Satoko, '
    'Satomi, Sayaka, Sayuri, Seina, Setsuko, Shigeko, Shiori, Shizue, Shizuka, Shoko, Sora, Sumiko, Sumire, Suzuka, Suzume, '
    'Takako, Takara, Tama, Tamaki, Tamami, Terumi, Tokiko, Tomoe, Tomoka, Tomomi, Toyoko, Tsukasa, Tsukiko, Tsukushi, Umeko, '
    'Umika, Wakana, Yae, Yasuko, Yayoi, Yoko, Yoshie, Yoshiko, Yoshimi, Yoshino, Yui, Yuina, Yuka, Yukae, Yukari, Yuki, '
    'Yukie, Yukiko, Yukina, Yume, Yumeka, Yumena, Yumiko, Yumina, Yuna, Yuri, Yurika, Yuriko, Yurina, Yuu, Yuuka, Yuuko, Yuuri, '
    'Yuzu, Yuzuka, Yuzuki, Yuzumi, Yuzuna, Yuzuno, Yuzusa',
  );
  static final List<String> fr = _csv(
    'Emma, Louise, Jade, Alice, Chloé, Lina, Mia, Rose, Léa, Anna, Zoé, Manon, Camille, Sarah, Juliette, Inès, Lila, Lola, Eva, Pauline, '
    'Jeanne, Agathe, Clara, Ambre, Nina, Elena, Mathilde, Margaux, Amélie, Noémie, Romane, Elisa, Lucie, Victoire, Salomé, Maëlle, Maëlys, '
    'Maëva, Louna, Louane, Lou, Océane, Élodie, Émilie, Mélanie, Mélissa, Laurine, Laurie, Léonie, Léna, Apolline, Capucine, Constance, '
    'Faustine, Garance, Héloïse, Iris, Joséphine, Lise, Adèle, Aïcha, Alyssa, Amira, Anaëlle, Anouk, Aurore, Axelle, Bérénice, Carla, '
    'Caroline, Cassandre, Céleste, Célia, Celine, Charlotte, Coline, Coraline, Dominique, Éléna, Élise, Élodie, Émeline, Énora, Eugénie, '
    'Fanny, Florence, Gaëlle, Gaïa, Hélène, Ilona, Jade-Marie, Jeanne-Marie, Johanna, Judith, Justine, Karine, Laure, Laurie-Anne, Léa-Marie, '
    'Léa-Rose, Léa-Sophie, Léna-Rose, Lila-Rose, Lili, Lilou, Lison, Lorène, Louisa, Louise-Marie, Lucie-Rose, Maïa, Malika, Margot, Marion, '
    'Marjorie, Maud, Mélina, Morgane, Myriam, Nadia, Nadine, Naïma, Nawel, Noa, Noélie, Noëlle, Norah, Océane-Rose, Ophélie, Oriane, Perrine, '
    'Philippine, Priscilla, Rafaëlle, Raphaëlle, Roxane, Sabrina, Salma, Sandra, Sélène, Sidonie, Sofia, Solène, Sonia, Stéphanie, Suzanne, '
    'Suzette, Sylvie, Thaïs, Théa, Valentine, Valérie, Vanessa, Violette, Virginie, Yasmine, Zahra, Zoé-Lou, Zoé-Rose, Alix, Anaïs, Angélique, '
    'Annabelle, Ariane, Assia, Aude, Aveline, Billie, Blandine, Brigitte, Candice, Caroline-Rose, Clarisse, Clementine, Clotilde, Colombe, '
    'Daphné, Delphine, Désirée, Eglantine, Eléa, Eléna-Rose, Eliette, Elina, Eloane, Elya, Emeline, Emma-Rose, Enola, Erell, Estelle, '
    'Ethel, Eulalie, Fantine, Faustine-Rose, Flavie, Frédérique, Gaëtane, Gwendoline, Iliana, Isaline, Isadora, Isaline-Rose, Jade-Lou, '
    'Jade-Rose, Josépha, Juliette-Rose, June, Kaila, Kalie, Leïla, Léopoldine, Lila-Sophie, Lina-Rose, Line, Livia, Loïse, Lorraine, Lou-Ann, '
    'Louisa-Rose, Louise-Rose, Maïlys, Maïwenn, Malou, Manuelle, Maona, Maïa-Rose, Maylis, Mazarine, Méline, Milla, Nayah, Ninon, Noémie-Rose, '
    'Olympe, Philippine-Rose, Romy, Roxanne, Shana, Solange, Théodora, Tiphaine, Victoire-Rose',
  );
  static final List<String> de = _csv(
    'Mia, Emma, Hannah, Emilia, Sophia, Lina, Marie, Mila, Lea, Anna, Johanna, Leonie, Lara, Laura, Amelie, Luisa, Klara, Pauline, Charlotte, '
    'Nele, Leni, Ella, Alina, Frieda, Lotta, Greta, Mathilda, Ida, Emilia-Sophie, Lea-Sophie, Lea-Marie, Lena, Lena-Marie, Lena-Sophie, Lia, '
    'Liv, Maja, Melina, Mila-Sophie, Nele-Sophie, Paula, Pia, Sarah, Selina, Sophia-Marie, Sophie, Stella, Theresa, Valerie, Antonia, Annika, '
    'Carla, Elisa, Elisabeth, Finja, Franziska, Helene, Isabelle, Jette, Josefine, Juna, Jule, Karla, Katharina, Kim, Lara-Sophie, Lea-Rose, '
    'Lena-Rose, Leona, Liana, Lilli, Lina-Marie, Linnea, Livia, Lorena, Louisa, Luise, Luna, Marlene, Matilda, Merle, Mira, Miriam, Nadine, '
    'Nora, Paulina, Rebecca, Ronja, Sara, Selma, Sina, Sophia-Sophie, Tamara, Tessa, Thea, Viktoria, Viola, Yara, Zoe, Alisa, Anja, Annabell, '
    'Aylin, Beate, Bernadette, Bettina, Carina, Celina, Chiara, Corinna, Daniela, Deborah, Denise, Diana, Edith, Elke, Emely, Emilie, Erika, '
    'Eva, Fabienne, Felicia, Friederike, Giselle, Hannah-Marie, Hannelore, Heike, Helena, Henni, Ilona, Ina, Inga, Ines, Iris, Jana, Jasmin, '
    'Jennifer, Jessica, Johanna-Marie, Judith, Julia, Karina, Katrin, Kerstin, Lara-Marie, Laura-Marie, Lea-Helene, Lena-Helene, Leonie-Marie, '
    'Lieselotte, Lilli-Sophie, Lisanne, Lotte, Luana, Luzia, Madita, Magdalena, Margarete, Margot, Marika, Marina, Marlena, Martina, Melinda, '
    'Monika, Nadja, Nicole, Nina, Petra, Ramona, Romina, Rosalie, Sabine, Sandra, Saskia, Simone, Sonja, Stefanie, Svenja, Theresa-Marie, '
    'Ulrike, Vanessa, Verena, Viktoria-Marie, Viola-Marie, Vivien, Waltraud, Wanda, Wiebke, Xenia, Yvonne, Zoe-Marie',
  );
  static final List<String> it = _csv(
    'Sofia, Giulia, Aurora, Alice, Ginevra, Beatrice, Emma, Giorgia, Greta, Chiara, Martina, Francesca, Vittoria, Alessia, Bianca, Camilla, Anna, '
    'Sara, Valentina, Gaia, Noemi, Nicole, Arianna, Elisa, Elena, Ilaria, Lucia, Matilde, Caterina, Viola, Ludovica, Marta, Federica, Laura, '
    'Sabrina, Serena, Simona, Paola, Roberta, Francesca Maria, Maria Chiara, Maria Teresa, Maria Luisa, Maria Vittoria, Maria Sole, Maria Elena, '
    'Maria Giulia, Maria Grazia, Maria Pia, Anna Maria, Anna Chiara, Anna Rita, Anna Paola, Anna Laura, Anna Sofia, Anna Teresa, Carlotta, '
    'Claudia, Eleonora, Elisabetta, Eva, Francesca Sofia, Giorgia Maria, Giada, Giulia Maria, Ilenia, Isabella, Katia, Lara, Laura Maria, '
    'Letizia, Livia, Lucrezia, Ludmilla, Manuela, Margherita, Marianna, Marina, Marta Maria, Martina Sofia, Michela, Milena, Miriam, Monica, '
    'Nadia, Nadia Maria, Nadia Sofia, Nadia Chiara, Nadia Elena, Nadia Teresa, Naomi, Nicoletta, Ornella, Patrizia, Rachele, Rebecca, Rita, '
    'Rosalia, Rosanna, Rosita, Rossella, Sabrina Maria, Samantha, Samuela, Sara Maria, Silvia, Sonia, Stefania, Teresa, Valeria, Vanessa, Veronica, '
    'Vincenza, Virginia, Vittoria Maria, Zoe, Alessandra, Alessandra Maria, Angela, Angela Maria, Antonella, Barbara, Benedetta, Bruna, Carmela, '
    'Cecilia, Cinzia, Concetta, Costanza, Daniela, Deborah, Delia, Dora, Emanuela, Erica, Eufemia, Fabrizia, Filomena, Fiorenza, Fiorella, '
    'Flavia, Gemma, Imma, Ivana, Ivonne, Loredana, Lorena, Maddalena, Marcella, Mariella, Marilena, Marina Sofia, Marisa, Martina Maria, '
    'Matilda, Michela Maria, Mirella, Nadia Giorgia, Nadia Giulia, Nicole Maria, Noemi Maria, Paola Maria, Pamela, Patrizia Maria, Pierina, '
    'Raffaella, Renata, Romina, Rosamaria, Rosalinda, Sabrina Sofia, Santa, Savina, Serena Maria, Silvia Maria, Simona Maria, Susanna, Tamara, '
    'Tatiana, Tiziana, Veronica Maria, Vittoria Sofia, Ylenia, Zita',
  );
  static final List<String> pt = _csv(
    'Maria, Beatriz, Ana, Inês, Leonor, Matilde, Carolina, Margarida, Mariana, Sofia, Joana, Francisca, Lara, Luana, Gabriela, Rafaela, Letícia, '
    'Vitória, Helena, Isabel, Camila, Yasmin, Bruna, Daniela, Fernanda, Bianca, Larissa, Talita, Patrícia, Catarina, Andreia, Bárbara, Carlota, '
    'Madalena, Benedita, Cláudia, Diana, Eduarda, Fabiana, Filipa, Graça, Íris, Jéssica, Kátia, Lídia, Lívia, Lorena, Luísa, Madalena Sofia, '
    'Mafalda, Manuela, Marcela, Márcia, Margarida Sofia, Maria Alice, Maria Antônia, Maria Beatriz, Maria Cecília, Maria Clara, Maria Eduarda, '
    'Maria Fernanda, Maria Flor, Maria Gabriela, Maria Isabel, Maria Júlia, Maria Laura, Maria Luísa, Maria Rita, Maria Teresa, Marina, Marisa, '
    'Marta, Mayara, Melissa, Micaela, Milena, Mirela, Natália, Nicole, Noa, Patrícia Sofia, Paula, Raquel, Renata, Rita, Roberta, Rosa, Sílvia, '
    'Simone, Sofia Maria, Susana, Tânia, Tatiana, Telma, Teresa, Valentina, Vanessa, Vera, Vitória Maria, Vitória Sofia, Vitória Helena, Abigail, '
    'Adriana, Alessandra, Aline, Amanda, Amélia, Amora, Antônia, Aurora, Bela, Bia, Brenda, Cacilda, Cássia, Cecília, Celina, Chiara, Cléo, '
    'Conceição, Cristina, Dalila, Daniela Maria, Dayane, Débora, Eliana, Elisa, Elisandra, Eloá, Eloá Maria, Emília, Ester, Fabíola, Fátima, '
    'Flávia, Geovana, Giovana, Heloísa, Isabela, Isadora, Iara, Janaína, Joice, Júlia, Juliana, Karen, Karina, Larine, Lorena Maria, Luzia, '
    'Mahina, Malu, Manuela Sofia, Mariane, Mirella, Mônica, Nicole Maria, Pietra, Rafaela Maria, Rebeca, Sara, Sheila, Soraia, Taís, Valéria, '
    'Vitória Beatriz, Vitória Lorena, Yasmim, Zilda',
  );
  static final List<String> ru = _csv(
    'Sofia, Anastasia, Maria, Anna, Elena, Daria, Polina, Arina, Ksenia, Alina, Yulia, Victoria, Ekaterina, Natalia, Olga, Tatyana, Marina, '
    'Svetlana, Galina, Nadezhda, Valeria, Veronika, Kristina, Evgenia, Oksana, Alla, Inna, Irina, Zoya, Lyudmila, Elizaveta, Vasilisa, Ulyana, '
    'Pelageya, Varvara, Yana, Milana, Karina, Anfisa, Lilia, Yelena, Yevgeniya, Alyona, Albina, Angelina, Antonina, Aksinya, Tamara, Tatiana, '
    'Rimma, Regina, Rada, Raisa, Roza, Rosa, Snezhana, Sofiya, Stanislava, Taisiya, Ustinya, Vladislava, Yekaterina, Yelizaveta, Zinaida, '
    'Zhanna, Agata, Agnessa, Aglaya, Akulina, Alena, Alexandra, Alla-Maria, Alya, Anastasiya, Anfisa-Maria, Anna-Maria, Anya, Arisha, '
    'Avgustina, Bogdana, Darina, Dina, Domna, Ekaterina-Maria, Elina, Evelina, Feodora, Galina-Maria, Ilona, Inessa, Ivanna, Kira, Kristina-Maria, '
    'Lada, Larisa, Lidia, Lika, Lolita, Lyubov, Margarita, Mariya, Melaniya, Nika, Nina, Nonna, Olesya, Polina-Maria, Raisa-Maria, Regina-Maria, '
    'Roksana, Roza-Maria, Sabina, Snezhanna, Sofiya-Maria, Sonya, Tamila, Tatyana-Maria, Valentina, Vasilina, Viktoriya, Vlada, Yana-Maria, '
    'Yanina, Yarina, Yaroslava, Yelizaveta-Maria, Zlata, Adelina, Amina, Arina-Maria, Bella, Dana, Evelina-Maria, Iya, Ksenia-Maria, Liliya, '
    'Marya, Melisa, Mira, Mira-Maria, Nadezhda-Maria, Oksana-Maria, Radmila, Rima, Sofi, Taisiya-Maria, Varya, Vasilisa-Maria, Veronika-Maria, '
    'Vika, Violetta, Vita, Yevdokiya, Yevlampiya, Zarema, Zoya-Maria, Zvenislava, Zoya-Polina, Yara, Yuliana, Zlata-Maria',
  );
  static final List<String> zh = _csv(
    'Mei, Li, Ling, Hua, Lan, Ying, Fang, Na, Yan, Xiu, Rui, Qin, Jing, Hui, Fen, Juan, Xia, Xiao, Xin, Xue, Qian, Qiu, Ya, Yun, Yue, Yingying, '
    'Lili, Liling, Meiling, Meihua, Meixiu, Xiulan, Xiuying, Xiumei, Xiuzhen, Xiurong, Xiaohua, Xiaoling, Xiaomei, Xiaoyan, Xiaolian, Xiaoqin, '
    'Xiaorui, Xiaoxue, Xiaoyu, Xiaoyue, Xiaoyun, Xiaoqing, Qing, Qingqing, Qinghua, Qingling, Qingmei, Qingyan, Qingyun, Qiumei, Qiuying, '
    'Qiurong, Qiuyan, Qiuju, Qiuqiu, Rong, Ronghua, Rongling, Rongmei, Rongyan, Rongyun, Yanmei, Yanhua, Yanling, Yanxiu, Yanqing, Yanyan, '
    'Yunmei, Yunhua, Yunling, Yunxiu, Yunqing, Yunyun, Yuehua, Yueling, Yuemei, Yueyan, Yueyun, Yaxin, Yating, Yaqi, Yahui, Yajing, Yali, '
    'Yalin, Yanan, Yanzi, Yaping, Yaqian, Yaqing, Yaqiu, Yaoyao, Yating, Yuting, '
    'Yuchen, Yuxin, Yuxuan, Yujia, Yujing, Yulan, Yuling, Yumei, Yumin, Yuyan, Yuyu, Yutong, Yuwei, Yuyao, Chunhua, Chunmei, Chunyan, Chunxiu, '
    'Chunling, Chunyu, Chunxue, Chunrong, Chunqing, Xiang, Xiangling, Xiangmei, Xiangyan, Xiangyun, Zhen, Zhenzhen, Zhenhua, Zhenling, Zhenmei, '
    'Zhenyan, Zhenyun, Zhi, Zhihua, Zhiling, Zhimei, Zhiyan, Zhiyun, Ning, Ningning, Ninghua, Ningling, Ningmei, Ningyan, Aihua, Ailing, Aimei, '
    'Aiyan, Aiyun, Caihong, Caiyun, Caixia, Caimei, Cuifen, Cuihua, Cuiling, Cuimei, Cuiyan, Cuiyun, Guihua, Guiling, Guimei, Guiyan, Guiyun, '
    'He, Hehua, Heling, Hemei, Heyan, Heyun, Hong, Honghua, Hongling, Hongmei, Hongyan, Hongyun, Huahua, Hualing, Huamei, Huayan, Huayun, '
    'Huihua, Huiling, Huimei, Huiyan, Huiyun, Jiahui, Jiaqi, Jiaxin, Jianing, Jiayi, Jiajia, Lanying, Lanxin, Lanxiu, Lanmei, Lanyan, Lanyun',
  );
  // Nuevos idiomas añadidos
  static final List<String> nl = _csv(
    'Emma, Julia, Tess, Sophie, Mila, Sara, Anna, Eva, Noor, Isa, Lotte, Lisa, Roos, Evi, Femke, Sanne, Floor, Ilse, Bo, Julie, Fay, Liv, Yara, Zoë, '
    'Indy, Fien, Lara, Benthe, Maud, Mirte, Puck, Esmee, Nienke, Anouk, Lieke, Nina, Vera, Amber, Karlijn, Saskia',
  );
  static final List<String> sv = _csv(
    'Alice, Maja, Elsa, Astrid, Wilma, Ebba, Alma, Ella, Olivia, Freja, Agnes, Lilly, Alva, Vera, Saga, Nora, Selma, Ellen, Elvira, Klara, '
    'Felicia, Emilia, Lovisa, Isabella, Julia, Tuva, Signe, Matilda, Hedda, Tilda, Tyra, Linnea, Hilma, Ingrid, Sara, Amanda, Emelie, Hanna, Josefin, Moa',
  );
  static final List<String> no_ = _csv(
    'Nora, Emma, Ella, Olivia, Sofia, Ingrid, Alma, Frida, Leah, Sara, Thea, Maja, Ada, Julie, Hedda, Emilie, Tuva, Selma, Aurora, Linnea, '
    'Amalie, Sigrid, Mathilde, Live, Oda, Mari, Hanne, Karoline, Jenny, Victoria, Marie, Malin, Anne, Kristine, Helene, Silje, Camilla, Synne, Ragnhild, Kari',
  );
  static final List<String> fi = _csv(
    'Sofia, Aino, Eevi, Emma, Aada, Olivia, Siiri, Helmi, Lilja, Iida, Nea, Venla, Ella, Emilia, Linnea, Anni, Sanni, Lotta, Noora, Veera, '
    'Minna, Laura, Hannele, Kaisa, Maija, Salla, Hanna, Mira, Elina, Riikka, Outi, Tuuli, Suvi, Tiina, Katri, Johanna, Petra, Heidi, Jenni, Niina',
  );
  static final List<String> da = _csv(
    'Emma, Freja, Alma, Clara, Sophie, Laura, Anna, Ella, Ida, Olivia, Agnes, Alberte, Asta, Aisha, Maja, Lærke, Luna, Mathilde, Caroline, Josefine, '
    'Emilie, Frida, Mille, Silje, Signe, Sidsel, Katrine, Rikke, Julie, Marie, Sara, Cecilie, Nanna, Amalie, Tilde, Lea, Gry, Helene, Karen, Mette',
  );
  static final List<String> isl = _csv(
    'Anna, Emma, Emilía, Guðrún, Katrín, Kristín, Elín, Hildur, Sara, Ásta, Sigríður, Helga, Bryndís, Ásdís, Ragnheiður, Margrét, Erla, Laufey, '
    'Þóra, Ingibjörg, Jóhanna, Dagbjört, Berglind, Hrafnhildur, Kolbrún, Sólrún, Eyrún, Ragnhildur, Sóley, Sunna, Rakel, Alda, Halla, Lilja, '
    'Elísabet, Maríanna, Edda, Fanney, Telma, Dóra, Unnur',
  );
  static final List<String> el = _csv(
    'Maria, Eleni, Katerina, Sofia, Dimitra, Ioanna, Georgia, Vasiliki, Konstantina, Panagiota, Despina, Niki, Angeliki, Athina, Anastasia, '
    'Foteini, Paraskevi, Christina, Evangelia, Zoi, Irene, Effie, Theodora, Marilena, Alexandra, Athanasia, Polyxeni, Chrysa, Nefeli, Eirini, '
    'Kyriaki, Rafaela, Spyridoula, Charikleia, Ourania, Myrto, Argyro, Elissavet, Melina, Amalia',
  );
  static final List<String> roLang = _csv(
    'Maria, Andreea, Elena, Ioana, Alexandra, Gabriela, Ana, Adriana, Bianca, Diana, Mihaela, Cristina, Roxana, Simona, Alina, Nicoleta, Raluca, '
    'Oana, Denisa, Florina, Ramona, Irina, Teodora, Iulia, Larisa, Georgiana, Catalina, Loredana, Anca, Camelia, Veronica, Daniela, Sabina, '
    'Sorina, Patricia, Monica, Violeta, Marina, Paula, Valentina',
  );
  static final List<String> hrLang = _csv(
    'Ana, Marija, Ivana, Maja, Petra, Martina, Katarina, Kristina, Helena, Sara, Laura, Lucija, Ema, Magdalena, Tea, Iva, Marija Ana, Andrea, '
    'Antonia, Marija Ivana, Jelena, Tihana, Tamara, Nikolina, Matea, Nika, Marijana, Bruna, Dora, Klara, Lorena, Paula, Ena, Mirna, Nina, Tena, Sanja, Marina, Zrinka',
  );
  static final List<String> slLang = _csv(
    'Ana, Marija, Eva, Lara, Sara, Nika, Neža, Tjaša, Maja, Katja, Ajda, Živa, Kaja, Špela, Tinkara, Tina, Urška, Nina, Teja, Polona, Mojca, '
    'Alja, Klara, Julija, Zala, Pia, Vita, Veronika, Ines, Kristina, Monika, Petra, Doroteja, Tereza, Lea, Tamara, Jasna, Maša, Anja, Barbara',
  );
  static final List<String> bg = _csv(
    'Maria, Elena, Ivana, Viktoria, Desislava, Dimana, Yoana, Kristina, Tsvetelina, Gergana, Teodora, Simona, Denitsa, Poli, Petya, Velina, '
    'Nadezhda, Miglena, Ralitsa, Ivelina, Slavena, Yana, Bilyana, Albena, Rositsa, Stanislava, Kalina, Milena, Siyana, Daniela, Zornitsa, Violeta, '
    'Blagovesta, Tereza, Antoaneta, Aleksandra, Albina, Zlata, Lora, Marina',
  );
  static final List<String> sr = _csv(
    'Marija, Ana, Jelena, Milica, Jovana, Teodora, Katarina, Ivana, Sara, Tijana, Nevena, Marija Ana, Andrea, Bojana, Dragana, Vesna, Marina, '
    'Tamara, Tanja, Sanja, Aleksandra, Anja, Kristina, Milena, Danijela, Mirjana, Gordana, Ljiljana, Natasa, Ivona, Isidora, Ksenija, Sofija, Zorka, Olivera, Ljubica, Tatjana, Snežana',
  );
  static final List<String> meLang = _csv(
    'Ana, Marija, Milica, Jovana, Teodora, Katarina, Ivana, Sara, Tijana, Nevena, Andrea, Bojana, Dragana, Vesna, Marina, Tamara, Tanja, Sanja, '
    'Aleksandra, Kristina, Milena, Danijela, Gordana, Ljiljana, Natasa, Isidora, Ksenija, Sofija, Olivera, Ljubica, Tatjana, Snežana, Mirjana, Ivona, Zorka, Jelena',
  );
  static final List<String> baLang = _csv(
    'Amina, Lamija, Sara, Emina, Ajla, Nejra, Lejla, Merima, Amna, Hana, Nejla, Fatima, Esma, Selma, Džana, Ena, Naida, Dalia, Amela, Alisa, '
    'Jasmina, Azra, Maja, Melisa, Nejira, Meliha, Medina, Zehra, Ilda, Ilma, Amra, Hena, Lamia, Elma, Leila, Edina, Samira, Amila, Majda, Alma',
  );
  static final List<String> pl = _csv(
    'Anna, Maria, Katarzyna, Agnieszka, Małgorzata, Ewa, Barbara, Magdalena, Joanna, Aleksandra, Monika, Karolina, Marta, Weronika, Paulina, Zuzanna, '
    'Natalia, Emilia, Julia, Wiktoria, Helena, Kinga, Klaudia, Patrycja, Dominika, Sylwia, Iga, Alicja, Hanna, Maja, Oliwia, Gabriela, Nikola, Amelia, Lena, Dorota, Beata',
  );
  static final List<String> cs = _csv(
    'Anna, Eliška, Adéla, Tereza, Natálie, Karolína, Emma, Sofie, Viktorie, Kristýna, Klára, Veronika, Nikola, Barbora, Lucie, Nela, Ema, Michaela, '
    'Jana, Markéta, Kateřina, Zuzana, Alena, Denisa, Pavla, Petra, Iveta, Simona, Monika, Gabriela, Ivana, Kamila, Lenka, Radka, Romana, Šárka, Irena, Jitka, Hana, Dita',
  );
  static final List<String> skLang = _csv(
    'Sofia, Nina, Viktória, Natália, Ema, Emma, Hana, Laura, Tamara, Nela, Lucia, Kristína, Mária, Barbora, Michaela, Veronika, Katarína, Zuzana, '
    'Monika, Jana, Simona, Adriana, Petra, Alexandra, Ivana, Daniela, Silvia, Diana, Edita, Andrea, Klaudia, Lenka, Timea, Nicol, Romana, Alžbeta, Elena, Lýdia, Karolína, Rebeka',
  );
  static final List<String> tr = _csv(
    'Elif, Zeynep, Merve, Betül, Fatma, Ayşe, Emine, Hatice, Zehra, Esra, Hande, Ceren, Buse, Sude, Miray, İrem, Melis, Nazlı, Ecrin, Nehir, '
    'Nisa, Azra, Hira, Sena, Büşra, Kübra, Aylin, Aysel, Aydan, Dilara, Dilan, Derya, Gül, Gülsüm, Gökçe, Pınar, Selin, Selen, Şeyma, Elvan',
  );
  static final List<String> he = _csv(
    'Noa, Maya, Tamar, Yael, Shira, Talia, Yuval, Noya, Michal, Adi, Lia, Roni, Lihi, Romi, Hodaya, Hila, Eden, Or, Gal, Avigail, Naama, Maayan, '
    'Shani, Nitzan, Tehila, Lior, Amit, Sapir, Vered, Ayala, Rotem, Ofir, Ilil, Hadas, Dana, Rakefet, Ravit, Gili, Netta, Anat',
  );
  static final List<String> th = _csv(
    'Nicha, Nisa, Nattida, Natthaya, Waraporn, Siriporn, Kanyarat, Kanyaphat, Napaporn, Ratchada, Rungnapa, Supaporn, Thanyarat, Ploy, Pimchanok, '
    'Patcharaporn, Kulnapha, Jiraporn, Woranuch, Kanchana, Panadda, Chutima, Thipphawan, Arisa, Benjamas, Phawinee, Suthida, Nattaporn, Kanokwan, '
    'Kanokporn, Chanida, Chanikan, Phatcharin, Sai, Orn, Noon, Fon, Som, Namwan, Gift',
  );
  static final List<String> vi = _csv(
    'Linh, Lan, Hoa, Mai, Trang, Huong, Thao, Phuong, Anh, Ngoc, Quynh, Nhi, My, Vy, Uyen, Khanh, Thuy, Hanh, Hang, Diep, Loan, Lien, Thanh, Kieu, '
    'Tien, Dung, Ha, Dao, Chi, Giang, Yen, Nhung, Phuong Anh, Thi, Bich, Ly, Xuan, Thu, Tam, San',
  );
  static final List<String> id = _csv(
    'Siti, Dewi, Putri, Ayu, Wulan, Indah, Rani, Fitri, Nisa, Aulia, Dwi, Lestari, Sari, Dian, Rina, Rika, Melati, Citra, Nurul, Yuni, Rahayu, Eka, '
    'Ningsih, Puspita, Maharani, Kartika, Anisa, Zahra, Laras, Intan, Wati, Ayuni, Sarah, Putu, Ayunda, Ratna, Rahayuni, Safira, Aisyah, Diah',
  );
  static final List<String> ms = _csv(
    'Nur, Aisyah, Siti, Zainab, Fatimah, Nurul, Balqis, Zahra, Aina, Hajar, Hanis, Izzah, Amirah, Farah, Nadia, Nabila, Syafiqah, Adila, Dania, '
    'Damia, Sofea, Umairah, Qistina, Qaisara, Maisarah, Puteri, Irdina, Alya, Batrisyia, Hani, Huda, Yasmin, Syazana, Syahirah, Iman, Syuhada, '
    'Nurin, Qaireen, Mawar, Dahlia',
  );
  static final List<String> tl = _csv(
    'Maria, Ana, Angelica, Andrea, Camille, Carla, Catherine, Clarisse, Cristina, Danica, Dianna, Elaine, Erika, Fatima, Francesca, Gabriela, '
    'Hannah, Hazel, Irene, Isabel, Jamie, Jasmin, Joanna, Joy, Karen, Kristine, Leila, Liza, Lorraine, Mae, Margarita, Maria Fe, Maricel, Mariel, '
    'Michelle, Nicole, Patricia, Pauline, Samantha, Shaina',
  );
  static final List<String> km = _csv(
    'Srey, Sreyneang, Sreypov, Sreylin, Chantha, Chanthou, Sokha, Sokun, Sokny, Sophea, Sopheak, Sreynich, Sreyroth, Ratha, Rotha, Reaksmey, '
    'Leakena, Leakhena, Chenda, Vannary, Vicheka, Pisey, Ravy, Chariya, Monita, Monika, Malis, Sreymao, Sreyoun, Sreydeth, Sreyda, Sothea, '
    'Sotheary, Sreychea, Sreyneat, Navy, Phalla, Serey',
  );
  static final List<String> lo = _csv(
    'Chanthavone, Khamla, Chansy, Ketsana, Keovieng, Bounpheng, Dalavanh, Douangchan, Douangdeuane, Manivanh, Oulayvanh, Phet, Phetsamone, '
    'Somsanith, Somphorn, Somchit, Souk, Viengkham, Vilay, Vongdeuane, Noy, Mali, Thida, Boua, Lampheng, Keo, Bua, Dao, Kham, Khone, Khoun, '
    'Koun, Nankham, Nang, Phoukham, Sopha, Sone, Thip, Vanthong',
  );
  static final List<String> my = _csv(
    'Hnin, Htet Htet, Su Su, Thandar, Thazin, Thuzar, Aye Aye, May, Mi Mi, Zin Mar, Zin Zin, Nway, Phyu Phyu, Ei Ei, Cho Cho, Thiri, Khin, '
    'Nandar, Nan, Su Mon, Su Latt, Moe Moe, Hla Hla, Nwe Nwe, San San, Khine, Pwint, Nu Nu, Pyae Pyae, Yin Yin, Nwe Oo, Mya Mya, Saw, Nadi, Cherry, Snow, Honey, Moon, Pearl',
  );
  static final List<String> fj = _csv(
    'Adi, Mere, Litia, Ana, Asenaca, Losalini, Miriama, Salote, Akanisi, Kula, Sera, Makereta, Vani, Elenoa, Leba, Litiana, Melaia, Alisi, Asinate, '
    'Atelaite, Eta, Kelera, Ilisapeci, Milika, Kinisimere, Lavenia, Sisilia, Talei, Mereoni, Vilisi, Vasenai, Wati, Litia Ana, Asinate Mere',
  );
  static final List<String> ko = _csv(
    'Seo-yeon, Ji-woo, Ha-eun, Seo-hyun, Ji-yoo, Soo-yeon, Min-seo, Ji-min, Ye-eun, Yeon-woo, Da-hye, Eun-ji, Eun-seo, Hye-jin, Hye-won, Hye-min, '
    'Hyun-seo, Yu-jin, Yu-na, Yu-ri, Seon-yeong, Ga-young, Na-yeon, Ha-rin, Chae-won, Ji-hye, Su-ji, Su-bin, So-yeon, So-hee, Seo-yeong, Seul-gi, '
    'Bo-young, Bo-ram, Bo-ra, Hae-won, Hae-rin, Hye-su, Hye-ji, Hye-kyung, Hyo-jin, Hyo-rin, Hyo-seo, Hyo-yeon, In-na, In-young, In-hee, Ji-ah, '
    'Ji-ae, Ji-an, Ji-eun, Ji-hyun, Ji-won, Jin-ah, Jin-hee, Jin-kyung, Jin-seo, Jin-yeong, Joo-eun, Joo-hyun, Joo-yeon, Joon-hee, Ju-ah, Ju-eun, '
    'Jung-ah, Jung-eun, Jung-hye, Jung-min, Jung-yeon, Mi-jin, Mi-kyung, Mi-so, Mi-sun, Mi-yeon, Min-ji, Min-kyung, Min-seo, Min-young, Na-ra, '
    'Na-young, Ra-hee, Sae-byeok, Sae-rom, Sae-ron, Se-ah, Se-eun, Se-hee, Se-hyun, Se-jin, Se-kyung, Se-mi, Se-ra, Se-yeon, Se-young, Seo-hee, '
    'Seo-in, Seo-jin, Seo-ju, Seo-kyung, Seo-min, Seo-rin, Seo-won, Seon-a, Seon-hee, Seon-hwa, Seon-jin, Seon-mi, Seon-woo, Sol-yi, So-eun, '
    'So-hyun, So-jin, So-jung, So-min, So-young, Soo-ah, Soo-bin, Soo-hyun, Soo-jin, Soo-jung, Soo-min, Soo-young, Sun-hee, Sun-hwa, Sun-mi, '
    'Su-yeon, Su-yeong, Ye-rin, Ye-rim, Ye-sol, Ye-seo, Ye-won, Ye-jin, Ye-ju, Ye-kyung, Ye-lin, Ye-min, Ye-sul, Ye-yeong, Yeo-jin, Yeo-reum, '
    'Yeo-wool, Yeon-a, Yeon-hee, Yeon-jin, Yeon-joo, Yeon-seo, Yeon-su, Yeon-woo, Young-ae, Young-eun, Young-hee, Young-joo, Young-mi, Young-ran, '
    'Yoon-ah, Yoon-ji, Yoon-seo, Yu-ha, Yu-hee, Yu-hye, Yu-mi, Yu-seon, Yu-soo, Yu-yeon, Eun-ha, Eun-hye, Eun-kyung, Eun-mi, Eun-young',
  );
  static final List<String> hi = _csv(
    'Ananya, Aaradhya, Saanvi, Diya, Isha, Aditi, Priya, Pooja, Neha, Sneha, Riya, Nisha, Kavya, Tanya, Tanvi, Shreya, Swara, Meera, Sita, Gita, '
    'Sunita, Lakshmi, Radha, Radhika, Roshni, Ishita, Anushka, Aishwarya, Shraddha, Bhavna, Parvati, Jyoti, Komal, Kiran, Naina, Navya, Harshita, '
    'Prachi, Muskan, Payal, Palak, Pallavi, Parul, Preeti, Priyanka, Rachna, Radhika Priya, Rani, Reema, Rhea, Ritika, Ritu, Sakshi, Saloni, '
    'Sangeeta, Sanjana, Sapna, Sarika, Seema, Shalini, Shikha, Shilpa, Shivani, Shradha, Shruti, Shubhi, Shweta, Simran, Smita, Snehal, Sonal, '
    'Sonali, Soumya, Suhani, Sukanya, Sulakshana, Suman, Sunaina, Sunidhi, Supriya, Suvarna, Swati, Tanu, Trisha, Tripti, Tulika, Urmila, Urvi, '
    'Vaishali, Vaishnavi, Vandana, Varsha, Vasudha, Veena, Vidhi, Vidya, Vijaya, Yamini, Yashika, Yashvi, Zarna, Aakanksha, Aaliya, Aarohi, '
    'Aastha, Aayushi, Abha, Aditi Priya, Aesha, Afreen, Ahana, Akanksha, Akshita, Alia, Alisha, Alka, Alpana, Amisha, Amrita, Amrutaa, Anamika, '
    'Ananya Priya, Anika, Anjali, Anjita, Ankita, Anmol, Antara, Anubhuti, Anvi, Aparna, Apurva, Archana, Arpita, Arushi, Asavari, Ashima, '
    'Asmita, Astha, Atreyi, Avantika, Ayushi, Baani, Bhumika, Chandni, Charita, Damini, Darshana, Deepti, Deeksha, Devanshi, Dhara, Dimple, '
    'Dipti, Divya, Dolly, Ekta, Falguni, Gargi, Gayatri, Geeta, Gauri, Hansa, Harini, Heena, Heeral, Hemangi, Himani, Indira, Ishani, Jagriti, '
    'Janvi, Jasleen, Jasmin, Juhi, Kajal, Kalpana, Kamini, Kanika, Kanishka, Karishma, Kashi, Kashish, Kavita, Keerti, Keya, Khushi, Kirti, '
    'Kripa, Kritika, Lavanya, Laxmi, Leena, Lipika, Lipi, Madhu, Madhuri, Mahima, Maithili, Malati, Malika, Mallika, Mandira, Manisha, Manshi, '
    'Mantasha, Meenakshi, Megha, Mohini, Mridula, Namrata, Nandini, Narmada, Natasha, Nayana, Niharika, Nikita, Nilam, Nisha Rani, Nishi, Nitya',
  );
  static final List<String> ar = _csv(
    'Fatima, Aisha, Zainab, Mariam, Noor, Layla, Leila, Lina, Salma, Yasmin, Yasmine, Zahra, Sara, Hanan, Huda, Iman, Rania, Rawan, Reem, Rima, '
    'Nada, Amal, Sumaya, Samira, Sana, Sanaa, Aaliyah, Alia, Aya, Ayah, Basma, Bayan, Bushra, Dalia, Dalal, Dania, Dina, Doha, Duha, Eman, Farah, '
    'Fariha, Ghada, Hiba, Jana, Janaah, Jannah, Jowairiya, Jumana, Lama, Lamia, Latifa, Layan, Laila, Leen, Lina Noor, Lubna, Maha, Mahira, Malak, '
    'Manal, Maram, Mariya, Marwa, May, Maysoon, Meera, Mona, Munira, Nadia, Nadine, Naila, Najla, Nawal, Nesreen, Nida, Noura, Nuha, Omaima, Racha, '
    'Rahaf, Rahma, Rasha, Rawya, Rawan Noor, Rayan, Rehab, Ritaj, Rola, Ruba, Rula, Ruqayya, Saba, Sabah, Sahar, Sajida, Salima, Sameera, Sara Noor, '
    'Sawsan, Shahd, Shaimaa, Shams, Shaza, Shereen, Shirin, Soha, Suad, Suha, Sumaiya, Tamara, Tasneem, Wafa, Walaa, Ward, Yara, Yosra, Youmna, '
    'Yumna, Zeina, Zeinab, Zohra, Zoya, Zubaida, Zulaikha, Zunaira, Afaf, Afnan, Ahlam, Amal Noor, Amira, Anfal, Arwa, Asala, Asma, Asrar, Atyaf, '
    'Ayat, Ayda, Aziza, Balqis, Batoul, Deema, Dima, Ebtisam, Elham, Eman Noor, Fadwa, Fajer, Fajr, Fatin, Fawzia, Fayza, Ghaliya, Halima, Haneen, '
    'Hanin, Hasna, Hawra, Hayat, Hayfa, Hessa, Hind, Israa, Jihan, Kalthoum, Karima, Kawthar, Khaoula, Khadija, Kholoud, Lamees, Maram Noor, Mariah, '
    'Marjan, Mayada, Mayar, Miral, Muna, Nermine, Nighat, Nour, Omnia, Rawanah, Riham, Rim, Sabreen, Safa, Sahira, Salwa, Samar, Samya, Shahed',
  );

  // Mezcla varias listas manteniendo el orden y sin duplicados, con límite opcional
  static List<String> _mergeUnique(List<List<String>> sources, {int? max}) {
    final seen = <String>{};
    final out = <String>[];
    for (final list in sources) {
      for (final name in list) {
        if (seen.add(name)) {
          out.add(name);
          if (max != null && out.length >= max) return out;
        }
      }
    }
    return out;
  }

  // Mapea ISO2 → lista base por idioma
  static List<String> forCountry(String? iso2) {
    if (iso2 == null) return es;
    switch (iso2.toUpperCase()) {
      // Específicos por idioma
      case 'JP':
        return jp;
      case 'FR':
        return fr;
      case 'DE':
        return de;
      case 'IT':
        return it;
      case 'PT':
      case 'BR':
        return pt;
      case 'RU':
      case 'UA':
        return ru;
      case 'CN':
        return zh;
      case 'KR':
      case 'KP':
        return ko;
      // Idiomas europeos nórdicos y NL
      case 'NL':
        return nl;
      case 'NO':
        return no_;
      case 'SE':
        return sv;
      case 'FI':
        return fi;
      case 'DK':
        return da;
      case 'IS':
        return isl;
      // Europa oriental y balcánica con idiomas propios
      case 'CZ':
        return cs;
      case 'SK':
        return skLang;
      case 'GR':
        return el;
      case 'RO':
        return roLang;
      case 'HR':
        return hrLang;
      case 'SI':
        return slLang;
      case 'BG':
        return bg;
      case 'RS':
        return sr;
      case 'PL':
        return pl;

      // Oriente Medio y Asia con idiomas propios
      case 'TR':
        return tr;
      case 'IL':
        return he;
      case 'TH':
        return th;
      case 'VN':
        return vi;
      case 'ID':
        return id;
      case 'MY':
        return ms;
      case 'PH':
        return tl;
      case 'KH':
        return km;
      case 'LA':
        return lo;
      case 'MM':
        return my;
      case 'FJ':
        return fj;
      case 'IN':
      case 'PK':
      case 'NP':
      case 'LK':
        return hi;
      case 'SA':
      case 'EG':
      case 'SD':
      case 'LY':
        return ar;

      // Países multilingües (combinaciones)
      // RS ya definido arriba con serbio
      case 'LU': // Luxemburgo (FR/DE) - por si se añade
        return _mergeUnique([fr, de]);
      case 'PR': // Puerto Rico (ES/EN)
        return _mergeUnique([es, en]);
      case 'GQ': // Guinea Ecuatorial (ES/FR)
        return _mergeUnique([es, fr, pt]);
      case 'MT': // Malta (MT/EN) - aproximamos IT/EN
        return _mergeUnique([it, en]);
      case 'AD': // Andorra (CA/ES/FR) - aproximamos ES/FR
        return _mergeUnique([es, fr]);
      case 'BE': // Bélgica (NL/FR/DE)
        return _mergeUnique([nl, fr, de]);
      case 'CH': // Suiza (DE/FR/IT)
        return _mergeUnique([de, fr, it]);
      case 'CA': // Canadá (EN/FR)
        return _mergeUnique([en, fr]);
      case 'SG':
        return _mergeUnique([en, zh, ms]);
      case 'CY': // Chipre (EL/TR)
        return _mergeUnique([el, tr]);
      case 'CM': // Camerún (FR/EN)
        return _mergeUnique([fr, en]);
      case 'RW': // Ruanda (FR/EN aprox)
        return _mergeUnique([fr, en]);
      case 'BI': // Burundi (FR/EN aprox)
        return _mergeUnique([fr, en]);
      case 'TD': // Chad (FR/AR)
        return _mergeUnique([fr, ar]);
      case 'DJ': // Yibuti (FR/AR)
        return _mergeUnique([fr, ar]);
      case 'LB': // Líbano (AR/FR)
        return _mergeUnique([ar, fr]);
      case 'MA': // Marruecos (AR/FR aprox)
        return _mergeUnique([ar, fr]);
      case 'DZ': // Argelia (AR/FR aprox)
        return _mergeUnique([ar, fr]);
      case 'TN': // Túnez (AR/FR aprox)
        return _mergeUnique([ar, fr]);
      case 'ME': // Montenegro (ME/SR/HR)
        return _mergeUnique([meLang, sr, hrLang]);
      case 'BA': // Bosnia y Herzegovina (BA/HR/SR)
        return _mergeUnique([baLang, hrLang, sr]);

      // Países hispanohablantes
      case 'ES':
        return es;
      case 'CO':
      case 'MX':
      case 'AR':
      case 'PE':
      case 'CL':
      case 'UY':
      case 'PY':
      case 'BO':
      case 'EC':
      case 'VE':
      case 'DO':
      case 'CU':
      case 'CR':
      case 'PA':
      case 'GT':
      case 'HN':
      case 'NI':
      case 'SV':
        return es;

      // Mundo anglófono o uso frecuente de EN
      case 'US':
      case 'GB':
      case 'IE':
      case 'AU':
      case 'NZ':
      case 'JM':
      case 'GM':
      case 'GH':
      case 'NG':
      case 'ET':
      case 'KE':
      case 'TZ':
      case 'UG':
      case 'ZA':
        return en;

      // Francófonos
      case 'SN':
      case 'CD':
      case 'HT':
        return fr;

      // Lusófonos
      case 'AO':
      case 'MZ':
        return pt;

      // Resto europeos aproximados
      case 'AT':
        return de;

      // Bálticos aproximados a EN
      case 'EE':
      case 'LV':
      case 'LT':
        return en;

      default:
        return es;
    }
  }

  /// Obtiene todos los códigos ISO2 soportados por el repositorio de nombres femeninos
  static Set<String> getSupportedCountryCodes() {
    return {
      'JP',
      'FR',
      'DE',
      'IT',
      'PT',
      'BR',
      'RU',
      'UA',
      'CN',
      'KR',
      'KP',
      'NL',
      'NO',
      'SE',
      'FI',
      'DK',
      'IS',
      'CZ',
      'SK',
      'GR',
      'RO',
      'HR',
      'SI',
      'BG',
      'RS',
      'PL',
      'TR',
      'IL',
      'TH',
      'VN',
      'ID',
      'MY',
      'PH',
      'KH',
      'LA',
      'MM',
      'FJ',
      'IN',
      'PK',
      'NP',
      'LK',
      'SA',
      'EG',
      'SD',
      'LY',
      'LU',
      'PR',
      'GQ',
      'MT',
      'AD',
      'BE',
      'CH',
      'CA',
      'SG',
      'CY',
      'CM',
      'RW',
      'BI',
      'TD',
      'DJ',
      'LB',
      'MA',
      'DZ',
      'TN',
      'ME',
      'BA',
      'ES',
      'CO',
      'MX',
      'AR',
      'PE',
      'CL',
      'UY',
      'PY',
      'BO',
      'EC',
      'VE',
      'DO',
      'CU',
      'CR',
      'PA',
      'GT',
      'HN',
      'NI',
      'SV',
      'US',
      'GB',
      'IE',
      'AU',
      'NZ',
      'JM',
      'GM',
      'GH',
      'NG',
      'ET',
      'KE',
      'TZ',
      'UG',
      'ZA',
      'SN',
      'CD',
      'HT',
      'AO',
      'MZ',
      'AT',
      'EE',
      'LV',
      'LT',
    };
  }
}
