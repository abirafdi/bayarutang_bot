require 'telegram/bot'

token = '334814720:AAFYszrLQ0BblusHQ5w9wdN4C8l5VkUTI-8'

Telegram::Bot::Client.run(token) do |bot|
    bot.listen do |message|
        case message.text
        when '/start'
            bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
        when '/utang'
            question = 'Siapa yang berhutang ke Anda?'
            # See more: https://core.telegram.org/bots/api#replykeyboardmarkup
            loaner =
            Telegram::Bot::Types::ReplyKeyboardMarkup
            .new(keyboard: [%w(Abi), %w(Octavina), %w(Marta)], one_time_keyboard: true)
            bot.api.send_message(chat_id: message.chat.id, text: question, reply_markup: loaner)

            howmuch = 'Berapa Banyak?'
            bot.api.send_message(chat_id: message.chat.id, text: howmuch)
            amount = message.text

            konfirmasi = 'Jadi si ' + loaner + ' berhutang sebanyak ' + amount + '. Apakah benar?'

            bot.api.send_message(chat_id: message.chat.id, text: question, reply_markup: konfirmasi)
        when '/stop'
            # See more: https://core.telegram.org/bots/api#replykeyboardremove
            kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
            bot.api.send_message(chat_id: message.chat.id, text: 'Sorry to see you go :(', reply_markup: kb)
        end
    end
end