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

/**
 * Opens the {{name}} dynamic form in a ModalForm.
 *
 * @module     {{component}}/{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

import ModalForm from 'core_form/modalform';
import Notification from 'core/notification';
import {add as addToast} from 'core/toast';
import {getString} from 'core/str';

/**
 * Opens the form when an element matching the selector is clicked; its data-* attributes become the form args.
 *
 * @param {string} selector Trigger elements, e.g. '[data-action="{{component}}-{{name}}"]'
 */
export const init = (selector) => {
    document.addEventListener('click', (e) => {
        const trigger = e.target.closest(selector);
        if (!trigger) {
            return;
        }
        e.preventDefault();
        const modalForm = new ModalForm({
            formClass: '{{component}}\\form\\{{name}}',
            args: {...trigger.dataset},
            modalConfig: {title: getString('{{titleid}}', '{{component}}')},
            returnFocus: trigger,
        });
        modalForm.addEventListener(modalForm.events.FORM_SUBMITTED, () => {
            getString('changessaved', 'moodle').then(addToast).catch(Notification.exception);
        });
        modalForm.show();
    });
};
