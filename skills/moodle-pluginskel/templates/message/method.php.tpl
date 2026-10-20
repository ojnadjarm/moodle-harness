    /**
     * Send the {{name}} notification to a user from the no-reply user.
     *
     * @param \stdClass $user recipient
     * @param string $subject subject and short text
     * @param string $text plain text body
     * @param \moodle_url $url page the notification links to
     * @return int|false message id, false when not sent
     */
    public static function send_{{name}}(\stdClass $user, string $subject, string $text, \moodle_url $url) {
        $message = new \core\message\message();
        $message->component = '{{component}}';
        $message->name = '{{name}}';
        $message->userfrom = \core_user::get_noreply_user();
        $message->userto = $user;
        $message->subject = $subject;
        $message->fullmessage = $text;
        $message->fullmessageformat = FORMAT_PLAIN;
        $message->fullmessagehtml = text_to_html(s($text));
        $message->smallmessage = $subject;
        $message->notification = 1;
        $message->contexturl = $url->out(false);
        $message->contexturlname = $subject;
        return message_send($message);
    }
