{{- define "application.volumeMounts.backend" }}
{{- if .Values.persistence.enabled }}
- mountPath: {{ .Values.persistence.spryker.data.mountPath | quote }}
  name: spryker-data-volume
{{- end }}
{{- end }}

{{- define "application.volumes.backend" }}
{{- if .Values.persistence.enabled }}
- name: spryker-data-volume
  persistentVolumeClaim:
    claimName: {{ tpl .Values.persistence.spryker.data.claimName $ | quote }}
{{- end }}
{{- end }}

{{- define "application.volumes.wwwDataPaths" }}
{{- if .Values.persistence.enabled }}
- {{ .Values.persistence.spryker.data.mountPath | quote }}
{{- end }}
{{- end }}
