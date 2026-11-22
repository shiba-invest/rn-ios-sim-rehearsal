// Practice login screen. Same parts and words as a common ID + password login:
// an entry button, an ID field ("例: 001"), a password field with a label, a login button, two failure messages.
// The fields keep their text after a failed try; the password is cleared only when the app goes to the background.
import { useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import {
  AppState, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { messageFor, signIn } from '../src/auth';

export default function Login() {
  const router = useRouter();
  const [view, setView] = useState<'start' | 'form'>('start');
  const [id, setId] = useState('');
  const [pw, setPw] = useState('');
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const sending = useRef(false);
  const tries = useRef(0);

  useEffect(() => {
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'background') setPw('');
    });
    return () => sub.remove();
  }, []);

  const submit = async () => {
    Keyboard.dismiss();
    if (sending.current) return;
    if (!id) { setErr('職員IDを入力してください'); return; }
    if (!pw) { setErr('パスワードを入力してください'); return; }
    sending.current = true;
    tries.current += 1;
    console.log(`[REHEARSAL] submit try=${tries.current}`);
    setErr(null);
    setBusy('パスワードを確認しています…');
    await new Promise((r) => setTimeout(r, 0));
    try {
      const out = await signIn(id.padStart(3, '0'), pw);
      console.log(`[REHEARSAL] sign-in ok outcome=${out} try=${tries.current}`);
      setBusy(null);
      router.replace('/home');
    } catch (e) {
      console.log(`[REHEARSAL] sign-in failed code=${(e as { code?: string })?.code ?? 'unknown'} try=${tries.current}`);
      setBusy(null);
      setErr(messageFor(e));
    } finally {
      sending.current = false;
    }
  };

  return (
    <SafeAreaView style={styles.root} edges={['top', 'left', 'right']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <ScrollView contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <Text style={styles.brand}>れんしゅう</Text>
          {view === 'start' ? (
            <View style={styles.block}>
              <Pressable style={styles.primary} onPress={() => setErr('ID・パスワードでログインしてください')}>
                <Text style={styles.primaryText}>顔・指紋でログイン</Text>
              </Pressable>
              <Pressable style={styles.secondary} onPress={() => { setErr(null); setView('form'); }}>
                <Text style={styles.secondaryText}>ID・パスワードでログイン</Text>
              </Pressable>
              {err ? <Text style={styles.err}>{err}</Text> : null}
            </View>
          ) : (
            <View style={styles.block}>
              <Text style={styles.label}>職員ID</Text>
              <TextInput
                style={styles.input}
                value={id}
                onChangeText={setId}
                keyboardType="number-pad"
                placeholder="例: 001"
                testID="loginId"
                autoCapitalize="none"
                autoCorrect={false}
                textContentType="username"
              />
              <Text style={styles.label}>パスワード</Text>
              <View style={styles.pwRow}>
                <TextInput
                  style={[styles.input, styles.flex]}
                  value={pw}
                  onChangeText={setPw}
                  placeholder="パスワード"
                  testID="loginPw"
                  secureTextEntry={!show}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="ascii-capable"
                  returnKeyType="go"
                  onSubmitEditing={submit}
                />
                <Pressable
                  style={styles.eye}
                  accessibilityRole="button"
                  accessibilityLabel={show ? 'パスワードを隠す' : 'パスワードを表示'}
                  onPress={() => setShow((v) => !v)}
                >
                  <Text>{show ? '◉' : '◎'}</Text>
                </Pressable>
              </View>
              {err ? <Text style={styles.err}>⚠ {err}</Text> : null}
              <Pressable style={styles.primary} onPress={submit}>
                <Text style={styles.primaryText}>ログイン</Text>
              </Pressable>
            </View>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
      {busy ? (
        <View style={styles.overlay}>
          <Text style={styles.overlayText}>{busy}</Text>
        </View>
      ) : null}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff' },
  flex: { flex: 1 },
  body: { padding: 24, gap: 16, justifyContent: 'center', flexGrow: 1 },
  brand: { fontSize: 32, textAlign: 'center', marginBottom: 16 },
  block: { gap: 12 },
  label: { fontSize: 14, color: '#555' },
  input: { borderWidth: 1, borderColor: '#999', borderRadius: 8, minHeight: 48, paddingHorizontal: 12, fontSize: 18 },
  pwRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  eye: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  err: { color: '#c0392b', fontSize: 15 },
  primary: { backgroundColor: '#2e7d32', borderRadius: 10, minHeight: 52, alignItems: 'center', justifyContent: 'center' },
  primaryText: { color: '#fff', fontSize: 18 },
  secondary: { borderWidth: 1, borderColor: '#999', borderRadius: 10, minHeight: 48, alignItems: 'center', justifyContent: 'center' },
  secondaryText: { fontSize: 16 },
  overlay: { ...StyleSheet.absoluteFill, backgroundColor: 'rgba(255,255,255,0.9)', alignItems: 'center', justifyContent: 'center' },
  overlayText: { fontSize: 18 },
});
