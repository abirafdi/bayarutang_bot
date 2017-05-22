require 'telegram/bot'

token = '334814720:AAFYszrLQ0BblusHQ5w9wdN4C8l5VkUTI-8'

Telegram::Bot::Client.run(token) do |bot|
    utang_lock = 0
    loanee = ''
    amount = 0

    lunasi_lock = 0
    tombok_lock = 0

    bot.listen do |message|
        # Hutang Case
        if utang_lock > 0
            if  utang_lock == 1
                kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch, reply_markup: kb)
                loanee = message.text
                utang_lock += 1
            elsif utang_lock == 2
                amount = message.text.to_i
                konfirmasi = 'Jadi ' + loanee + ' berhutang sebanyak ' + amount.to_s + ' kepada Anda'
                bot.api.send_message(chat_id: message.chat.id, text: konfirmasi)
                utang_lock = 0
            end
        # Lunasin Case
        elsif lunasi_lock > 0
            if  lunasi_lock == 1
                kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch, reply_markup: kb)
                loanee = message.text
                lunasi_lock += 1
            elsif lunasi_lock == 2
                amount = message.text.to_i
                konfirmasi = 'Jadi ' + loanee + ' melunasi sebanyak ' + amount.to_s + ' kepada Anda'
                bot.api.send_message(chat_id: message.chat.id, text: konfirmasi)
                lunasi_lock = 0
            end
        # Tombokin Case
        elsif tombok_lock > 0
            if  tombok_lock == 1
                howmuch = 'Berapa Banyak?'
                bot.api.send_message(chat_id: message.chat.id, text: howmuch)
                loanee = message.text
                tombok_lock += 1
            elsif tombok_lock == 2
                amount = message.text.to_i
                konfirmasi = 'Jadi ' + loanee + ' melunasi sebanyak ' + amount.to_s + ' kepada Anda'
                bot.api.send_message(chat_id: message.chat.id, text: konfirmasi)
                tombok_lock = 0
            end
        else
            case message.text
            when '/start'
                bot.api.send_message(chat_id: message.chat.id, text: "Hello, @#{message.from.username} with id #{message.from.id}")
            when '/utang'
                utang_lock += 1
                
                answers = Telegram::Bot::Types::ReplyKeyboardMarkup
                .new(keyboard: [['Abi Rafdi'],['Orang Selanjutnya'],['Lai Terus']], one_time_keyboard: true)

                question = 'Siapa yang berhutang ke Anda?'
                bot.api.send_message(chat_id: message.chat.id, text: question, reply_markup: answers)
            when '/lunasi'
                lunasi_lock += 1
                question = 'Siapa yang melunasi ke Anda?'
                bot.api.send_message(chat_id: message.chat.id, text: question)
            when '/tombok'
                tombok_lock += 1
                question = 'Barang Apa Yang Anda Tombok?'
                bot.api.send_message(chat_id: message.chat.id, text: question)
            when '/stop'
                # See more: https://core.telegram.org/bots/api#replykeyboardremove
                bot.api.send_message(chat_id: message.chat.id, text: 'Sorry to see you go :(', reply_markup: kb)
            end
        end
    end
end