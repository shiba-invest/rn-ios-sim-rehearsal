import { useRouter } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

export default function Home() {
  const router = useRouter();
  return (
    <View style={styles.root}>
      <Text style={styles.title}>ホーム</Text>
      <Text>The request reached the server and came back.</Text>
      <Pressable accessibilityRole="button" accessibilityLabel="ホーム" style={styles.card} onPress={() => { console.log('[REHEARSAL] home card press'); router.push('/list'); }}>
        <Text style={styles.cardText}>一覧をひらく</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, backgroundColor: '#fff' },
  title: { fontSize: 28 },
  card: { minHeight: 44, paddingHorizontal: 24, justifyContent: 'center', borderRadius: 8, backgroundColor: '#e8eef8' },
  cardText: { fontSize: 18 },
});
