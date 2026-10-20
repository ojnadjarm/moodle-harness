    /**
     * Renders the {{name}} widget from its template.
     *
     * @param {{name}} $widget Widget to render
     * @return string HTML
     */
    public function render_{{name}}({{name}} $widget): string {
        return $this->render_from_template('{{component}}/{{name}}', $widget->export_for_template($this));
    }
