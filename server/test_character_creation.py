"""Creation rejection messages preserve native codes, ownership and retryability."""
import unittest
from eo_session import Session,CharacterCreationError,Reader,number,string


def session(replies):
    s=Session.__new__(Session);s.characters=[dict(id=1,name='existing')];s.sent=[]
    s.send=lambda f,a,p=b'':s.sent.append((f,a,p))
    pending=iter(replies);s.wait=lambda *args,**kwargs:next(pending)
    return s


class CreationTests(unittest.TestCase):
    def test_reasons_match_native_creation_codes_without_replacing_owned_characters(self):
        for code,message in [(1,'already taken'),(2,'no free character slots'),(4,'4–12 letters'),(99,'code 99')]:
            s=session([number(77,2)+b'OK',number(code,2)])
            with self.subTest(code=code),self.assertRaises(CharacterCreationError) as error:
                s.create_character('another')
            self.assertEqual(error.exception.code,code)
            self.assertIn(message,str(error.exception))
            self.assertEqual(s.characters,[dict(id=1,name='existing')])
            self.assertEqual(s.sent[0],(3,1,string('NEW')))

    def test_retry_after_name_collision_uses_a_fresh_native_operation(self):
        s=session([number(77,2)+b'OK',number(1,2),number(78,2)+b'OK',number(5,2)+number(0,1)+b'\x01\xff'])
        with self.assertRaisesRegex(CharacterCreationError,'already taken'):s.create_character('existing')
        self.assertEqual(s.create_character('newname'),{'characters':[]})
        self.assertEqual([Reader(p).num(2) for f,a,p in s.sent if a==6],[77,78])

if __name__=='__main__':unittest.main()
