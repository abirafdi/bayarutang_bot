require 'telegram/bot'
require 'sqlite3'

# ====================== GLOBAL VARIABLES ====================== # 

token = ENV["BAYAR_UTANG_TOKEN"]

begin
    db = SQLite3::Database.open "hutang.db"
    puts "Connected to SQLite3 Database"
    puts "Bot Ready"
rescue SQLite3::Exception => e
    puts "Failed to connect to SQLite3"
    puts e
end

# ====================== SUPPORTING FUNCTIONS ====================== # 

def regischeck(db,user_id)
    query = "SELECT * FROM users WHERE user_id=#{user_id}" 
    rs = db.execute(query)

    if rs.length > 0
        return true
    else
        raise "Id #{user_id} is not registered"
    end
end

def getuserchoice(db,user_id)
    names = []
    users = Hash.new

    query = "SELECT * FROM users" 
    rs = db.execute(query)

    rs.each do |user|
        if user[0].to_s != user_id.to_s
            names << ["#{user[1]} #{user[2]}"]
            users["#{user[1]} #{user[2]}"] = user[0]
        end
    end

    return Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: names, one_time_keyboard: true), users
end

def insert_rel(db,loanee_id,loaner_id, amount)
    begin
        db.execute "INSERT INTO hutang_rel(loanee_id,loaner_id,amount) VALUES(#{loanee_id},#{loaner_id},#{amount})"
    rescue => e
        db.execute "UPDATE hutang_rel SET amount = amount + #{amount} WHERE loanee_id=#{loanee_id} AND loaner_id=#{loaner_id}"
    end
end

def daftar_hutang(db, user_id)
    user_data = Hash.new
    plus = Hash.new
    minus = Hash.new

    query_user = "SELECT * FROM users"
    rs_user = db.execute(query_user)

    query_trx = "SELECT * FROM hutang_rel WHERE loaner_id=#{user_id}"
    rs_trx = db.execute(query_trx)

    rs_user.each do |user|
        user_data[user[0].to_s] = user[3]
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
    users = []

    bot.listen do |message|
        if(sess[message.from.id] == nil)
            sess[message.from.id] = Hash.new
            sess[message.from.id]['loanee'] = ''
            sess[message.from.id]['loanee_id'] = ''
            sess[message.from.id]['amount'] = 0
            sess[message.from.id]['u_lock'] = 0
            sess[message.from.id]['l_lock'] = 0
        end

        loanee = sess[message.from.id]['loanee']
        loanee_id = sess[message.from.id]['loanee_id']
        amount = sess[message.from.id]['amount']

        if message.text == '/cancel'
            sess[message.from.id]['u_lock'] = 0
            sess[message.from.id]['l_lock'] = 0

            notification = 'Okay, task cancelled'
            bot.api.send_message(chat_id: message.chat.id, text: notification)
        end

        # Hutang Case
        if sess[message.from.id]['u_lock'] > 0
            if  sess[message.from.id]['u_lock'] == 1
                kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch, reply_markup: kb)
                sess[message.from.id]['loanee'] = message.text
                sess[message.from.id]['loanee_id'] = users[message.text]
                sess[message.from.id]['u_lock'] += 1
            elsif sess[message.from.id]['u_lock'] == 2
                amount = message.text.to_i
                sess[message.from.id]['amount'] = amount
                nice_amt = amount.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                konfirmasi = "Oh, jadi *#{loanee}* berhutang sebanyak *#{nice_amt}* ke kamu. Apakah sudah benar? Kirim '_Ya, Benar_' untuk konfirmasi"
                bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', text: konfirmasi)
                sess[message.from.id]['u_lock'] += 1
            elsif sess[message.from.id]['u_lock'] == 3 and message.text == 'Ya, Benar'
                db.execute "INSERT INTO hutang_log(loaner_id,loanee_id,amount) VALUES(#{message.from.id},#{loanee_id},#{amount})"
                insert_rel(db, loanee_id, message.from.id, (amount * -1))
                konfirmasi = 'Mudah2an cepat dibayar ya! sudah kita catat'
                bot.api.send_message(chat_id: message.chat.id, text: konfirmasi)
                sess[message.from.id]['u_lock'] = 0
            end
        # Lunasin Case
        elsif sess[message.from.id]['l_lock'] > 0
            if  sess[message.from.id]['l_lock'] == 1
                kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch, reply_markup: kb)
                sess[message.from.id]['loanee'] = message.text
                sess[message.from.id]['loanee_id'] = users[message.text]
                sess[message.from.id]['l_lock'] += 1
            elsif sess[message.from.id]['l_lock'] == 2
                amount = message.text.to_i
                sess[message.from.id]['amount'] = amount
                nice_amt = amount.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                konfirmasi = "Oh, jadi *#{loanee}* melunasi sebanyak *#{nice_amt}* ke kamu. Apakah sudah benar? Kirim '_Ya, Benar_' untuk konfirmasi"
                bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', text: konfirmasi)
                sess[message.from.id]['l_lock'] += 1
            elsif sess[message.from.id]['l_lock'] == 3 and message.text == 'Ya, Benar'
                db.execute "INSERT INTO lunas_log(loaner_id,loanee_id,amount) VALUES(#{message.from.id},#{loanee_id},#{amount})"
                insert_rel(db, loanee_id, message.from.id, amount)
                konfirmasi = 'Asiik selamat ya! sudah kita catat'
                bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', text: konfirmasi)
                sess[message.from.id]['l_lock'] = 0
            end
        # Tombokin Case [Coming Soon]
        # elsif tombok_lock > 0
        #     if  tombok_lock == 1
        #         howmuch = 'Berapa Banyak?'
        #         bot.api.send_message(chat_id: message.chat.id, text: howmuch)
        #         loanee = message.text
        #         tombok_lock += 1
        #     elsif tombok_lock == 2
        #         amount = message.text.to_i
        #         konfirmasi = 'Jadi ' + loanee + ' melunasi sebanyak ' + amount.to_s + ' ke kamu'
        #         bot.api.send_message(chat_id: message.chat.id, text: konfirmasi)
        #         tombok_lock = 0
        #     end
        else
            case message.text
            when '/start'
                begin
                    db.execute "INSERT INTO users VALUES(#{message.from.id},'#{message.from.first_name}','#{message.from.last_name}','#{message.from.username}')"
                    bot.api.send_message(chat_id: message.chat.id, text: "Welcome to the hutang world, @#{message.from.username}")
                rescue => e
                    bot.api.send_message(chat_id: message.chat.id, text: "Gausah tulis /start lagi, @#{message.from.username}! Lagi banyak hutang apa banyak yang ngutang?")
                    puts e
                end
            when '/hutang'
                begin
                    regischeck(db,message.from.id)
                    sess[message.from.id]['u_lock'] += 1
                    
                    answers,users = getuserchoice(db,message.from.id)
                    question = 'Siapa yang ngutang ke kamu?'
                    bot.api.send_message(chat_id: message.chat.id, text: question, reply_markup: answers)
                rescue => e
                    puts e
                    question = "Please register first, #{message.from.first_name}. Type /start to start using this app!"
                    bot.api.send_message(chat_id: message.chat.id, text: question)
                end
            when '/lunas'
                begin
                    regischeck(db,message.from.id)
                    sess[message.from.id]['l_lock'] += 1

                    answers,users = getuserchoice(db,message.from.id)
                    question = 'Siapa yang lunasin hutang ke kamu?'
                    bot.api.send_message(chat_id: message.chat.id, text: question, reply_markup: answers)
                rescue => e
                    puts e
                    question = "Please register first, #{message.from.first_name}. Type /start to start using this app!"
                    bot.api.send_message(chat_id: message.chat.id, text: question)
                end
            when '/daftarhutang'
                begin
                    regischeck(db,message.from.id)

                    user_data, plus, minus = daftar_hutang(db,message.from.id)
                    out_text = ''

                    if plus.length > 0
                        out_text = "Berikut ini adalah daftar hutang-hutang kamu:  \nDan "
                    end

                    plus.each do |key, value|
                        uname = user_data[key]
                        amount = value.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                        out_text += "*-* Kamu berhutang ke @#{uname} sebanyak *#{amount}*  \n"
                    end
    
                    if minus.length > 0
                        out_text += "\nini adalah daftar orang yang berhutang sama kamu:  \n"
                    end

                    minus.each do |key, value|
                        uname = user_data[key]
                        amount = value.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
                        out_text += "*-* @#{uname} berhutang ke kamu sebanyak *#{amount}*  \n"
                    end

                    if plus.length == 0 and minus.length == 0
                        out_text += "Kamu tidak terkait dengan hutang apapun. Selamat! Kamu bebas dari lingkaran perhutangan"
                    else
                        out_text += "\nSemoga semua urusan hutang kamu dilancarkan ya"
                    end

                    bot.api.send_message(chat_id: message.chat.id, parse_mode: 'Markdown', text: out_text)
                rescue => e
                    puts e
                    question = "Please register first, #{message.from.first_name}. Type /start to start using this app!"
                    bot.api.send_message(chat_id: message.chat.id, text: question)
                end
            when '/help'
                help = "Halo, #{message.from.first_name}! Thanks sudah menggunakan @bayarutangbot \n\n"
                help += "Bayar Utang Bot adalah sebuah bot yang bisa mencatat kegiatan perhutangan kamu, jadi kamu gak bakal lupa kalo ada yang ngutang sama kamu. Apalagi kalo kamu yang ngutang haha. Mudah-mudahan kita semua terbebas dari hutang ya! Jangan banyak ngutang gaes!\n\n"
                help += "Mau berkontribusi? Pull request aja di https://github.com/abirafdi/bayarutang_bot"
                bot.api.send_message(chat_id: message.chat.id, text: help)
            when '/howto'
                how = "Kalau kamu belum pernah terdaftar, ketik /start untuk memulai menggunakan bot \n"
                how += "Untuk mencatat hutang seseorang ke kamu, ketik /hutang lalu pilih nama yang berhutang ke kamu dan tuliskan nominalnya\n"
                how += "Untuk mencatat pelunasan seseorang ke kamu, ketik /lunas lalu pilih nama yang melunasi ke kamu dan tuliskan nominalnya\n"
                how += "Untuk melihat keadaan perhutangan kamu, ketik /daftarhutang\n\n"
                how += "Saat ini pencatatan baru bisa dilakukan dari sisi yang dihutangi."
                bot.api.send_message(chat_id: message.chat.id, text: how)
            # Tombokan Coming Soon
            # when '/tombok'
            #     tombok_lock += 1
            #     question = 'Barang Apa Yang Anda Tombok?'
            #     bot.api.send_message(chat_id: message.chat.id, text: question)
            # when '/stop'
            #     bot.api.send_message(chat_id: message.chat.id, text: 'Sorry to see you go :(', reply_markup: kb)
            end
        end
    end
end