{{!
    This file is part of Moodle - https://moodle.org/

    Moodle is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Moodle is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Moodle.  If not, see <https://www.gnu.org/licenses/>.
}}
{{!
    @template {{component}}/{{template}}

    Moodle App page of the {{handler}} handler: Ionic markup, strings via the app translate pipe.

    Example context (json):
    {}
}}
{{=<% %>=}}
<ion-list>
    <ion-item>
        <ion-label>
            <h2>{{ 'plugin.{{component}}.pluginname' | translate }}</h2>
            <p>{{ 'plugin.{{component}}.{{stringid}}' | translate }}</p>
        </ion-label>
    </ion-item>
{{rowsmarkup}}</ion-list>
