--- @revenant-script
--- name: arkati
--- version: 1.0.0
--- author: Pukk
--- game: gs
--- description: Display Arkati (deity) lore information
--- tags: arkati, deity, lore, reference
---
--- Usage:
---   ;arkati <name>    - Display info about a specific Arkati
---   ;arkati list      - List all known Arkati
---   ;arkati           - Show usage

local deities = {}

deities["charl"] = function()
    respond("<preset id='whisper'>Charl, Lord of the Seas</preset>")
    respond("<preset id='whisper'>God of the Oceans, Storms and Revolution</preset>")
    respond("")
    respond("Charl is the God of the Sea. Living apart from his brethren, he dwells constantly in the seas of Elanthia, joining the other Gods only when Koar commands. Legend holds that Koar once had to send for Charl six times before he appeared. When Koar demanded to know why he was so disobedient, Charl replied that he was always the most obedient of Koar's servants, but that the waters of the six oceans of the world flowed through his veins, and none could come without the others.")
    respond("Charl is a dark and violent god, and is renowned for his drastic mood swings. He cares little for the land dwelling races on Elanthia, and is as likely to swat a nearby ship with a storm as he is to let it pass untouched. Because of this he is feared by seamen, and few pray to him for fear they might attract his attention. For the same reason clerics serving Charl, although seldom welcome, rarely come to harm in any place frequented by seamen.")
    respond("")
    respond("He is also the god of storms of all sorts, and more than one despotic tyrant, overthrown by an angry mob marching under a stormy sky, has sworn that it was Charl's hand that laid him low.")
    respond("")
    respond("Some clergy contend that Charl is at heart a God of Darkness. Still, there is little doubt that he swears fealty to Koar, and for that reason, if for no other, he is numbered with the Gods of Light.")
    respond("")
    respond("Charl's preferred humanoid manifestation is that of a towering man with a beard of seaweed and algae, blue and grey robes, wielding a trident. Charl rarely appears except in the sea or the heart of a storm. His lower half is a fish's tail. In manner, he is stern, angry and quick-tempered. His symbol is an emerald trident on a field of blue.")
    respond("")
end

deities["cholen"] = function()
    respond("<preset id='whisper'>Cholen, the Jester</preset>")
    respond("<preset id='whisper'>God of Festivals, Performing Arts, and Humor (Pantheon of Liabo)</preset>")
    respond("")
    respond("Cholen is the God of festivals and the performing arts. The offspring of Imaera and Eonak, he is the twin brother of Jastev.")
    respond("Patron of celebrations and all that goes with them, Cholen is renowned for his bright demeanor, his mastery of music, song, and dance, and of his mischievous nature. All performing skills commonly seen at festivals fall within his domain, and muttered prayers to Cholen are not uncommon among jugglers, actors, and bards who frequently perform at them.")
    respond("")
    respond("The many comedies whose plots revolve around mistaken identity and cross-gender disguises owe their basis, at least in part, to Cholen's penchant for cross-gender pranks, although his disguises are generally acknowledged as being more complete than most acting troupes could ever manage.")
    respond("")
    respond("Cholen's preferred humanoid manifestation is that of a young man with summer-sun gold hair, blue eyes and a slight build. He is arrayed in fine but exaggerated clothing, and he favors a great cloak with patches of every color and shape imaginable. In manner, he is playful and mocking. His symbol is a crimson lute on a field of gold.")
end

deities["eonak"] = function()
    respond("<preset id='whisper'>Eonak, Master of the Forge</preset>")
    respond("<preset id='whisper'>God of Craftsmanship, Labor and Triumph Over Adversity (Pantheon of Liabo)</preset>")
    respond("")
    respond("Eonak is the artificer of the gods. He is also the consort of Imaera. After the Ur-Daemon War, he took the people who worked in the stone under his wing and taught them. Thus, he is considered the patron of the dwarves.")
    respond("Maker of all of the fantastic items used by the gods, Eonak spends most of his time at his forge. He is more at home there than anywhere else, and at times only a decree from Koar or the soft words of Imaera can separate him from it.")
    respond("")
    respond("Often considered a strange pairing, Imaera and Eonak are each masters of crafting, although their choices of substances is vastly different. Imaera's crafting is of living things, of cycles and seasons and balance. Eonak's crafting is of inanimate things, yet even as Imaera's, his creations must fulfill their purposes, achieve a balance of beauty and utility, and all, even as Imaera's do, contain some part of him that marks them as creations of Eonak's hand.")
    respond("")
    respond("Eonak personifies success won by hard work rather than natural gifts alone. Legends differ as to how Eonak lost his arm, but all agree that the veil iron arm he spent lifetimes crafting is the greatest piece of craftsmanship ever undertaken and serves him better than the original.")
    respond("")
    respond("Eonak's preferred humanoid manifestation is that of a heavily muscled, soot-covered man with a veil iron arm. His manner is generally taciturn and focused, but given to bouts of merry-making. His symbol is a golden anvil on a field of brown.")
end

deities["imaera"] = function()
    respond("<preset id='whisper'>Imaera, Lady of the Green</preset>")
    respond("<preset id='whisper'>Goddess of Nature, the Harvest, and Healing (Pantheon of Liabo)</preset>")
    respond("")
    respond("Imaera is the Goddess of the natural world and all its bounty. She is the patroness of the sylvan elves. The consort of Eonak, she is the mother of Jastev and Cholen.")
    respond("The most powerful of the gods in the sphere of life and growing things, Imaera exercises her power most frequently in her oversight of the seasons and the harvest. As the bringer of Autumn, she is also the Goddess of the harvest. When a life passes to the beyond, it passes through her hands, and the transition from life to death falls within her power.")
    respond("")
    respond("As a healer, Imaera is without peer among the gods, for the body is of nature, and she alone is the mistress of nature. Among the lesser gods, Kuon is her closest companion, as his love of the forest places him frequently within her domain.")
    respond("")
    respond("Imaera's preferred humanoid manifestation is that of a young woman with flowing auburn hair. She is arrayed in robes of green and brown, covered with leaves and vines. In manner, she is earthy, warm, and giving. Her symbol is a golden sheaf of grain on a field of green.")
end

deities["koar"] = function()
    respond("<preset id='whisper'>Koar, King of the Gods</preset>")
    respond("<preset id='whisper'>God of Justice, Loyalty, and Law (Pantheon of Liabo)</preset>")
    respond("")
    respond("Koar is King of the Gods, and the most powerful of the Arkati. He is the only Arkati whose origin is questioned, as some believe him to be a surviving Drake. He has also been called the most powerful of the Great Spirits by the followers of the Way.")
    respond("Legends surrounding Koar are many and varied, and some of them contradict each other severely. Most agree that it was Koar who first rallied the Arkati to the cause of the peoples of Elanthia during the Ur-Daemon War, and that without him, the Drakes' mortal servants would have been destroyed.")
    respond("")
    respond("The most powerful of all the gods, Koar is rarely seen. But when he appears, the whole of Elanthia takes note. He is considered to be the most fair and just of all the gods, and it is his judgment that the others defer to in times of conflict.")
    respond("")
    respond("Koar's preferred humanoid manifestation is that of an elderly man with a long white beard and piercing grey eyes. He is arrayed in simple robes of white and gold. In manner, he is stern but just, imposing but kind. His symbol is a golden crown on a field of white.")
end

deities["lorminstra"] = function()
    respond("<preset id='whisper'>Lorminstra, the Gatekeeper</preset>")
    respond("<preset id='whisper'>Goddess of Death, Rebirth, and Winter (Pantheon of Liabo)</preset>")
    respond("")
    respond("Lorminstra is the Goddess of death and rebirth. She is the keeper of the gate through which the dead must pass on their way to the beyond. The youngest daughter of Koar and Lumnis, she is also the Goddess of Winter.")
    respond("While many view death as something to be feared, Lorminstra views it as a natural part of the cycle of life. She is compassionate and caring, and she grieves for those who pass through her gate. She is the most human of the gods in her emotional responses.")
    respond("")
    respond("Lorminstra's preferred humanoid manifestation is that of a wan, beautiful young woman dressed in a black robe. Her symbol is a gold key on a field of black.")
end

deities["lumnis"] = function()
    respond("<preset id='whisper'>Lumnis, the Wise</preset>")
    respond("<preset id='whisper'>Goddess of Wisdom, Knowledge, and Learning (Pantheon of Liabo)</preset>")
    respond("")
    respond("Lumnis is the Goddess of wisdom and knowledge. She is the mate of Koar and the mother of Lorminstra and Ronan.")
    respond("The keeper of all knowledge, Lumnis is often sought out by those who would learn. While she is generous with her knowledge, she is also wise enough to know that some knowledge is dangerous, and she guards such secrets carefully.")
    respond("")
    respond("Lumnis's preferred humanoid manifestation is that of a tall, stately woman with piercing blue eyes and long silver hair. She is arrayed in robes of grey and silver. In manner, she is serene, wise, and patient. Her symbol is a golden scroll on a field of grey.")
end

deities["oleani"] = function()
    respond("<preset id='whisper'>Oleani, the Bride</preset>")
    respond("<preset id='whisper'>Goddess of Love, Fertility, and Spring (Pantheon of Liabo)</preset>")
    respond("")
    respond("Oleani is the Goddess of love and fertility. She is the embodiment of spring and all it represents: new life, new love, and new beginnings.")
    respond("The patron of lovers and marriages, Oleani blesses unions and watches over families. She is the most gentle of the gods, and her presence is felt in every flower that blooms and every child that is born.")
    respond("")
    respond("Oleani's preferred humanoid manifestation is that of a beautiful young woman with long golden hair and warm brown eyes. She is arrayed in flowing robes of white and pink, adorned with fresh flowers. In manner, she is warm, loving, and nurturing. Her symbol is a red heart on a field of white.")
end

deities["phoen"] = function()
    respond("<preset id='whisper'>Phoen, the Sun King</preset>")
    respond("<preset id='whisper'>God of the Sun, Summer, and Fatherhood (Pantheon of Liabo)</preset>")
    respond("")
    respond("Phoen is the God of the sun and of summer. He is the mate of Oleani and the brother of Ronan.")
    respond("The bringer of light and warmth to the world, Phoen is revered by all who depend on the sun for their livelihood. Farmers pray to him for good growing seasons, and travelers give thanks for his light that guides their way.")
    respond("")
    respond("Phoen's preferred humanoid manifestation is that of a tall, bronze-skinned man with golden hair that seems to glow with its own light. He is arrayed in robes of gold and orange. In manner, he is bold, forthright, and generous. His symbol is a golden sunburst on a field of blue.")
end

deities["ronan"] = function()
    respond("<preset id='whisper'>Ronan, the Night</preset>")
    respond("<preset id='whisper'>God of Night, Dreams, and Guardians (Pantheon of Liabo)</preset>")
    respond("")
    respond("Ronan is the God of night and darkness. He is the son of Koar and Lumnis, and the brother of Phoen.")
    respond("The master of dreams and the keeper of the night, Ronan patrols the darkness to protect the sleeping from the things that lurk within it. He is the patron of those who stand guard while others sleep.")
    respond("")
    respond("Ronan's preferred humanoid manifestation is that of a young man dressed in black robes, with dark hair and piercing dark eyes. In manner, he is quiet, watchful, and brooding. His symbol is a black sword on a field of white.")
end

deities["tonis"] = function()
    respond("<preset id='whisper'>Tonis, the Swift</preset>")
    respond("<preset id='whisper'>God of Speed, Travel, and Thieves (Pantheon of Liabo)</preset>")
    respond("")
    respond("Tonis is the God of speed and travel. He is the fastest of the gods, and the patron of travelers, messengers, and thieves.")
    respond("The swiftest of all beings, mortal or divine, Tonis is always on the move. He carries messages between the gods and is the patron of all who must move quickly. His blessing is sought by travelers for safe and swift journeys.")
    respond("")
    respond("Tonis's preferred humanoid manifestation is that of a lean, wiry young man dressed in traveling clothes. He is always in motion, fidgeting, pacing, or tapping his foot. His symbol is a golden lightning bolt on a field of blue.")
end

-- Dark Arkati

deities["luukos"] = function()
    respond("<preset id='whisper'>Luukos, the Serpent</preset>")
    respond("<preset id='whisper'>God of Death, Undeath, and Decay (Pantheon of Lornon)</preset>")
    respond("")
    respond("Luukos is the God of death, undeath, and decay. He is the master of the undead and the patron of necromancers.")
    respond("Where Lorminstra sees death as a natural passage, Luukos sees it as a tool to be exploited. He delights in the corruption of the living and the enslavement of the dead. His followers seek to cheat death through undeath, a perversion that draws the ire of Lorminstra and her followers.")
    respond("")
    respond("Luukos's preferred humanoid manifestation is that of a green-scaled serpent-man with slitted eyes. His symbol is a green serpent on a field of black.")
end

deities["mularos"] = function()
    respond("<preset id='whisper'>Mularos, Lord of Suffering</preset>")
    respond("<preset id='whisper'>God of Suffering, Domination, and Romantic Love Perverted (Pantheon of Lornon)</preset>")
    respond("")
    respond("Mularos is the God of suffering and domination. He is the dark mirror of Oleani, representing love twisted into obsession and possession.")
    respond("His followers believe that true devotion can only be proven through pain and sacrifice. They practice rituals of suffering that they believe bring them closer to their dark patron.")
    respond("")
    respond("Mularos's preferred humanoid manifestation is that of a pale, beautiful young man with sorrowful eyes and a cruel smile. His symbol is a black heart pierced by a silver nail.")
end

deities["sheru"] = function()
    respond("<preset id='whisper'>Sheru, the Bringer of Night</preset>")
    respond("<preset id='whisper'>God of Night, Terror, and Nightmares (Pantheon of Lornon)</preset>")
    respond("")
    respond("Sheru is the God of night and terror. He is the dark mirror of Ronan, and where Ronan guards the sleeping, Sheru sends nightmares to torment them.")
    respond("The master of fear and terror, Sheru delights in the suffering of those who sleep. His followers practice dark rituals designed to spread fear and madness.")
    respond("")
    respond("Sheru's preferred humanoid manifestation is that of a black jackal with burning red eyes. His symbol is a pair of red eyes on a field of black.")
end

deities["v'tull"] = function()
    respond("<preset id='whisper'>V'tull, the Berserker</preset>")
    respond("<preset id='whisper'>God of War, Bloodlust, and Destruction (Pantheon of Lornon)</preset>")
    respond("")
    respond("V'tull is the God of war and destruction. He is the most violent of the dark gods, reveling in combat and bloodshed for its own sake.")
    respond("Where Kai represents martial honor and discipline, V'tull represents war at its most brutal and mindless. His followers seek only to destroy, and they revel in the chaos of battle.")
    respond("")
    respond("V'tull's preferred humanoid manifestation is that of a massive, scarred warrior covered in blood. His symbol is a red sword on a field of black.")
end

-- Neutral Arkati

deities["zelia"] = function()
    respond("<preset id='whisper'>Zelia, the Madwoman</preset>")
    respond("<preset id='whisper'>Goddess of the Moons, Madness, and Wanderers</preset>")
    respond("")
    respond("Zelia is the Goddess of the moons and of madness. She is one of the neutral Arkati, belonging to neither Liabo nor Lornon.")
    respond("The mistress of lunacy and of dreams gone awry, Zelia is unpredictable and capricious. Her moods shift with the moons, and her followers are often considered mad by the standards of normal society.")
    respond("")
    respond("Zelia's preferred humanoid manifestation is that of a wild-haired woman with ever-changing features. Her symbol is a silver crescent moon on a field of black.")
end

deities["kai"] = function()
    respond("<preset id='whisper'>Kai, the Champion</preset>")
    respond("<preset id='whisper'>God of Athletic Prowess, Strength, and Martial Arts (Pantheon of Liabo)</preset>")
    respond("")
    respond("Kai is the God of physical strength and athletic prowess. He is the patron of warriors, athletes, and all who value physical excellence.")
    respond("The most physically powerful of the gods, Kai values honor in combat and athletic achievement. His followers strive to perfect their bodies and their fighting skills.")
    respond("")
    respond("Kai's preferred humanoid manifestation is that of a tall, powerfully built young man with dark hair and keen eyes. He is arrayed in simple fighting clothes. In manner, he is direct, confident, and honorable. His symbol is a silver fist on a field of blue.")
end

deities["jastev"] = function()
    respond("<preset id='whisper'>Jastev, the Seer</preset>")
    respond("<preset id='whisper'>God of Visual Arts, Prophecy, and Dreams (Pantheon of Liabo)</preset>")
    respond("")
    respond("Jastev is the God of visual arts and prophecy. He is the twin brother of Cholen, and the son of Imaera and Eonak.")
    respond("The patron of artists and prophets, Jastev sees the future in visions and expresses what he sees through art. His followers are often painters, sculptors, and seers.")
    respond("")
    respond("Jastev's preferred humanoid manifestation is that of a thin, pale young man with distant, unfocused eyes. He is arrayed in paint-stained robes. His symbol is a silver eye on a field of blue.")
end

-- List of all known deities
local deity_names = {}
for name, _ in pairs(deities) do
    table.insert(deity_names, name)
end
table.sort(deity_names)

local arg = Script.vars[1]

if not arg or arg == "" then
    echo("Usage: ;arkati <deity name>")
    echo("       ;arkati list")
    echo("")
    echo("Available Arkati: " .. table.concat(deity_names, ", "))
    return
end

local name = arg:lower()

if name == "list" then
    echo("Known Arkati:")
    echo("")
    for _, dname in ipairs(deity_names) do
        echo("  " .. dname)
    end
    return
end

if deities[name] then
    deities[name]()
else
    echo("Unknown Arkati: " .. arg)
    echo("Try: ;arkati list")
end
