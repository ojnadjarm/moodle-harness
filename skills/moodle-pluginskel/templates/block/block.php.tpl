<?php
{{header}}

/**
 * Block {{component}}.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{component}} extends block_base {
    /**
     * Initialises the block title.
     */
    public function init() {
        $this->title = get_string('pluginname', '{{component}}');
    }

    /**
     * Returns the block content.
     *
     * @return stdClass
     */
    public function get_content() {
{{#block_list}}
        global $DB, $USER;

{{/block_list}}
        if ($this->content !== null) {
            return $this->content;
        }

        $this->content = new stdClass();
        $this->content->text = '';
        $this->content->footer = '';
{{#block_list}}
        $rows = $DB->get_records('{{table}}', ['userid' => $USER->id], 'id DESC', 'id, {{field}}', 0, 5);
        $items = [];
        foreach ($rows as $row) {
            $items[] = format_string($row->{{field}}, true, ['context' => $this->context]);
        }
        if ($items) {
            $this->content->text = html_writer::alist($items);
        }
        $url = new moodle_url('/blocks/{{pluginname}}/{{link}}');
        $this->content->footer = html_writer::link($url, get_string('viewall', '{{component}}'));
{{/block_list}}
        return $this->content;
    }

    /**
     * Pages where the block can be added.
     *
     * @return array
     */
    public function applicable_formats() {
        return [
            'admin' => false,
            'site-index' => true,
            'course-view' => true,
            'mod' => false,
            'my' => true,
        ];
    }
{{#has_settings}}

    /**
     * The block has a settings.php file.
     *
     * @return bool
     */
    public function has_config() {
        return true;
    }
{{/has_settings}}
}
