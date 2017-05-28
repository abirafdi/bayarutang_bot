require 'telegram/bot'
require 'sqlite3'

# ====================== GLOBAL VARIABLES ====================== # 

token = ENV["BAYAR_UTANG_TOKEN"]

begin
    db = SQLite3::Database.open "bayarutang_bot_stg.db"
    puts "Connected to SQLite3 Database"
    puts "Bot Ready"
rescue SQLite3::Exception => e
    puts "Failed to connect to SQLite3"
    puts e
end

# ====================== SUPPORTING FUNCTIONS ====================== # 

def regischeck(db,user_id,chat_id)
    query = "SELECT * FROM users WHERE user_id=#{user_id} AND chat_id=#{chat_id}" 
    rs = db.execute(query)

    if rs.length > 0
        return true
    else
        raise "Id #{user_id} is not registered in this chat room!"
    end
end

def getuserchoice(db,user_id,chat_id)
    names = []
    users = Hash.new

    query = "SELECT * FROM users WHERE chat_id=#{chat_id}" 
    rs = db.execute(query)

    rs.each do |user|
        if user[0].to_s != user_id.to_s
            names << ["#{user[2]} #{user[3]}"]
            users["#{user[2]} #{user[3]}"] = user[0]
        end
    end

    return Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: names, one_time_keyboard: true, selective: true), users
end

def insert_rel(db,loanee_id,loaner_id,amount,chat_id)
    # active side
    begin
        db.execute "INSERT INTO utang_rel(loanee_id,loaner_id,amount,chat_id) VALUES(#{loanee_id},#{loaner_id},#{amount},#{chat_id})"
    rescue => e
        db.execute "UPDATE utang_rel SET amount = amount + #{amount} WHERE loanee_id=#{loanee_id} AND loaner_id=#{loaner_id} AND chat_id=#{chat_id}"
    end

    # passive side
    begin
        db.execute "INSERT INTO utang_rel(loanee_id,loaner_id,amount,chat_id) VALUES(#{loaner_id},#{loanee_id},#{amount * -1},#{chat_id})"
    rescue => e
        db.execute "UPDATE utang_rel SET amount = amount + #{amount * -1} WHERE loanee_id=#{loaner_id} AND loaner_id=#{loanee_id} AND chat_id=#{chat_id}"
    end
end

def daftar_utang(db,user_id,chat_id)
    user_data = Hash.new
    plus = Hash.new
    minus = Hash.new

    query_user = "SELECT * FROM users WHERE chat_id=#{chat_id}"
    rs_user = db.execute(query_user)

    query_trx = "SELECT * FROM utang_rel WHERE loaner_id=#{user_id} AND chat_id=#{chat_id}"
    rs_trx = db.execute(query_trx)

    rs_user.each do |user|
        if user[4] == ''
            user_data[user[0]] = "#{user[2]} #{user[3]}"
        else
            user_data[user[0]] = "@#{user[4]}"
        end
    end

    rs_trx.each do |trx|
        if trx[3] > 0
            plus[trx[1]] = trx[3]
        elsif trx[3] < 0
            minus[trx[1]] = trx[3] * -1
        end
    end

    return user_data, plus, minus
end

# ====================== BOT LISTENER START ====================== # 

Telegram::Bot::Client.run(token) do |bot|
    sess = Hash.new
    users = nil

    bot.listen do |message|
        # Value to make writing easier
        usr_id = message.from.id
        sess_id = "#{usr_id}-#{message.chat.id}"
        puts "[#{sess_id}] #{message.text}" # debug

        # Init session
        if(sess[sess_id] == nil)
            sess[sess_id] = Hash.new
            sess[sess_id]['temp'] = ''
            sess[sess_id]['other_id'] = ''
            sess[sess_id]['amount'] = 0
            sess[sess_id]['u_lock'] = 0
            sess[sess_id]['l_lock'] = 0
            sess[sess_id]['task'] = nil
        end

        puts "Session data #{sess_id}: #{sess[sess_id]}" # debug

        # Init variables
        task = sess[sess_id]['task']

        # Global Cancel
        if message.text == '/cancel' or message.text == '/cancel@bayarutangbot'
            sess[sess_id]['u_lock'] = 0
            sess[sess_id]['l_lock'] = 0

            kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true, selective: true)
            notification = 'Okay, task cancelled'
            bot.api.send_message(chat_id: message.chat.id, text: notification, reply_markup: kb)
        end

        # utang Case
        if sess[sess_id]['u_lock'] > 0
            if sess[sess_id]['u_lock'] == 1 # Ask the utang mode
                task['other_name'] = message.text
                task['other_id'] = task['users'][message.text]
                sess[sess_id]['u_lock'] += 1

                jenis = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: [['Berutang'],['Mengutangi']], one_time_keyboard: true, selective: true)
                question = 'Berutang atau mengutangi?'
                bot.api.send_message(chat_id: message.chat.id, reply_to_message_id: message.message_id, text: question, reply_markup: jenis)

            elsif sess[sess_id]['u_lock'] == 2 # Ask how much 
                task['type'] = message.text
                sess[sess_id]['u_lock'] += 1

                # kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true, selective: true)
                reply = Telegram::Bot::Types::ForceReply.new(force_reply: true, selective: true)
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch, reply_to_message_id: message.message_id, reply_markup: reply)

            elsif sess[sess_id]['u_lock'] == 3
                task['amount'] = message.text
                nice_amt = task['amount'].to_s.reverse.gsub(/...(?=.)/,'\&,').reverse

                sess[sess_id]['u_lock'] += 1

                confirm = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: [['Iya'],['Lah kata siapa?']], one_time_keyboard: true, selective: true)

                case task['type']
                when 'Berutang'
                    konfirmasi = "Wah, jadi lu ngutang sebanyak *#{nice_amt}* ke *#{task['other_name']}*. Beneran?"
                    bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', reply_to_message_id: message.message_id, text: konfirmasi, reply_markup: confirm)
                when 'Mengutangi'
                    konfirmasi = "Oh, jadi si *#{task['other_name']}* ngutang sebanyak *#{nice_amt}* ke lu. Yakin udah benar?"
                    bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', reply_to_message_id: message.message_id, text: konfirmasi, reply_markup: confirm)
                end

            elsif sess[sess_id]['u_lock'] == 4
                puts task #debug
                kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true, selective: true)

                case message.text
                when 'Iya'
                    case task['type']
                    when 'Berutang'
                        db.execute "INSERT INTO utang_log(loaner_id,loanee_id,amount,chat_id) VALUES(#{task['other_id']},#{usr_id},#{task['amount']},#{message.chat.id})"
                        insert_rel(db, usr_id, task['other_id'], (task['amount'].to_i * -1), message.chat.id)
                        konfirmasi = 'Udah kita catet nih. Jangan lupa dibayar tuh, dosa!'
                    when 'Mengutangi'
                        db.execute "INSERT INTO utang_log(loaner_id,loanee_id,amount,chat_id) VALUES(#{usr_id},#{task['other_id']},#{task['amount']},#{message.chat.id})"
                        insert_rel(db, task['other_id'], usr_id, (task['amount'].to_i * -1), message.chat.id)
                        konfirmasi = 'Mudah2an cepat dibayar ya! Udah kita catat'
                    end
                    
                    bot.api.send_message(chat_id: message.chat.id, reply_to_message_id: message.message_id, text: konfirmasi, reply_markup:kb)
                when 'Lah kata siapa?'
                    konfirmasi = 'Ah dasar tukang bohong!'
                    bot.api.send_message(chat_id: message.chat.id, reply_to_message_id: message.message_id, text: konfirmasi, reply_markup: kb)
                end
                
                sess[sess_id]['u_lock'] = 0
            end

        else
            # handle group command with botname
            if message.text == nil
                next
            end

            temp = message.text.split(" ")
            command = temp[0]
            param = temp[1..-1]

            split = command.split("@")
            if split.length > 1 and split[1] != 'bayarutangbot'
                next
            end
            input = split[0]

            case input
            when '/start'
                begin
                    db.execute "INSERT INTO users VALUES(#{usr_id},#{message.chat.id},'#{message.from.first_name}','#{message.from.last_name}','#{message.from.username}')"
                    bot.api.send_message(chat_id: message.chat.id, text: "Welcome to the utang world, @#{message.from.username}")
                rescue => e
                    bot.api.send_message(chat_id: message.chat.id, text: "Gausah tulis /start lagi, @#{message.from.first_name}! Lagi banyak utang apa banyak yang ngutang?")
                    puts e
                end

            when '/utang'
                begin
                    regischeck(db,usr_id,message.chat.id)

                    sess[sess_id]['u_lock'] += 1
                    sess[sess_id]['task'] = Hash.new
                    task = sess[sess_id]['task']
                    
                    answers,task['users'] = getuserchoice(db,usr_id,message.chat.id)
                    question = 'Siapa yang berurusan sama lu?'
                    bot.api.send_message(chat_id: message.chat.id, reply_to_message_id: message.message_id, text: question, reply_markup: answers)

                rescue Exception => e
                    puts e
                    question = "Please register first, #{message.from.first_name}. Type /start to start using this app!"
                    bot.api.send_message(chat_id: message.chat.id, text: question)
                end

            when '/daftarutang'
                begin
                    regischeck(db,usr_id,message.chat.id)

                    user_data, plus, minus = daftar_utang(db,usr_id,message.chat.id)
                    out_text = ''

                    if plus.length > 0
                        out_text = "Ini adalah daftar utang-utang kamu:  \n"
                    end

                    plus.each do |key, value|
                        uname = user_data[key]
                        amount = value.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                        out_text += "*-* Kamu berutang ke #{uname} sebanyak *#{amount}*  \n"
                    end
    
                    if minus.length > 0
                        out_text += "\nIni adalah daftar orang yang berutang sama kamu:  \n"
                    end

                    minus.each do |key, value|
                        uname = user_data[key]
                        amount = value.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                        out_text += "*-* #{uname} berutang ke kamu sebanyak *#{amount}*  \n"
                    end

                    if plus.length == 0 and minus.length == 0
                        out_text += "Kamu tidak terkait dengan utang apapun. Selamat! Kamu bebas dari lingkaran perutangan"
                    else
                        out_text += "\nSemoga semua urusan utang kamu dilancarkan ya"
                    end

                    bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', text: out_text)
                rescue => e
                    puts e
                    question = "Please register first, #{message.from.first_name}. Type /start to start using this app!"
                    bot.api.send_message(chat_id: message.chat.id, text: question)
                end

            when '/help'
                help = "Halo, #{message.from.first_name}! Thanks sudah menggunakan @bayarutangbot \n\n"
                help += "Bayar Utang Bot adalah sebuah bot yang bisa mencatat kegiatan perutangan kamu, jadi kamu gak bakal lupa kalo ada yang ngutang sama kamu. Apalagi kalo kamu yang ngutang haha. Mudah-mudahan kita semua terbebas dari utang ya! Jangan banyak ngutang gaes!\n\n"
                help += "Mau berkontribusi? Pull request aja di https://github.com/abirafdi/bayarutang_bot"
                bot.api.send_message(chat_id: message.chat.id, text: help)

            when '/howto'
                how = "Kalau kamu belum pernah terdaftar, ketik /start untuk memulai menggunakan bot \n"
                how += "Untuk mencatat utang seseorang ke kamu, ketik /utang lalu pilih nama yang berutang ke kamu, pilih arah utang, dan tuliskan nominalnya\n"
                how += "Untuk mencatat pelunasan seseorang ke kamu, ketik /lunas lalu pilih nama yang melunasi ke kamu, pilih arah pelunasan, dan tuliskan nominalnya\n"
                how += "Untuk melihat keadaan perutangan kamu, ketik /daftarutang\n\n"
                how += "Untuk membatalkan semua perintah, ketik /cancel"
                bot.api.send_message(chat_id: message.chat.id, text: how)
                
            end
        end
    end
end