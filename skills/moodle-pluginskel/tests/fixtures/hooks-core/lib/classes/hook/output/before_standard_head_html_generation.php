<?php
// This file is part of Moodle - http://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <http://www.gnu.org/licenses/>.

namespace core\hook\output;

/**
 * Allows plugins to add any elements to the page <head> html tag (trimmed from core 5.3).
 *
 * @package    core
 * @copyright  2023 Marina Glancy
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
#[\core\attribute\tags('output')]
#[\core\attribute\label('Allows plugins to add any elements to the page &lt;head&gt; html tag.')]
#[\core\attribute\hook\replaces_callbacks('before_standard_html_head')]
final class before_standard_head_html_generation {
}
