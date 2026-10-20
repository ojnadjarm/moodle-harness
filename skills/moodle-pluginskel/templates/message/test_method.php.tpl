    /**
     * send_{{name}} delivers one {{name}} notification to the user.
     */
    public function test_send_{{name}}(): void {
        $this->resetAfterTest();
        $user = $this->getDataGenerator()->create_user();
{{#capability}}
        $roleid = $this->getDataGenerator()->create_role();
        assign_capability('{{capability}}', CAP_ALLOW, $roleid, \context_system::instance());
        role_assign($roleid, $user->id, \context_system::instance());
{{/capability}}
        $sink = $this->redirectMessages();
        notifier::send_{{name}}($user, 'Subject', 'Body', new \moodle_url('/'));
        $messages = $sink->get_messages();
        $sink->close();
        $this->assertCount(1, $messages);
        $this->assertEquals($user->id, $messages[0]->useridto);
        $this->assertEquals('{{component}}', $messages[0]->component);
        $this->assertEquals('{{name}}', $messages[0]->eventtype);
    }
