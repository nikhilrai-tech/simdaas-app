
with open('/home/alex/Desktop/krishi-spray/simdaas-app/lib/features/data_monitoring/presentation/screens/monitoring_screen.dart', 'r') as f:
    content = f.read()
    open_braces = content.count('{')
    close_braces = content.count('}')
    print(f"Open: {open_braces}, Close: {close_braces}, Diff: {open_braces - close_braces}")
